import { Hono } from "hono";
import { sql, eq, and } from "drizzle-orm";
import { Env } from "../types";
import {
  audit_logs,
  transactions,
  transaction_items,
  item_types,
  buckets,
  users,
} from "../db/schema";
import { auth, requireRole } from "../middleware/auth";

const activityRoutes = new Hono<Env>();

activityRoutes.use("/*", auth(), requireRole("admin"));

// ─── Unified activity item shape returned to the frontend ───────────────────

interface ActivityItem {
  id: string;
  /** "bucket_created" | "bucket_updated" | "user_created" | "checkout" | … */
  action: string;
  actor_id: string;
  actor_name: string;
  /** Human-readable one-liner, e.g. "created Tent Pegs (SSB-TNT-912)" */
  summary: string;
  /** Structured detail for the expandable area */
  meta: Record<string, unknown> | null;
  created_at: string;
  /** Where this row came from — helps the frontend pick icons/colors */
  source: "audit" | "transaction";
}

// ─── GET /activity ──────────────────────────────────────────────────────────

activityRoutes.get("/", async (c) => {
  const db = c.get("db");

  const offset = Math.max(0, parseInt(c.req.query("offset") ?? "0", 10) || 0);
  const limit = Math.min(parseInt(c.req.query("limit") ?? "20", 10) || 20, 50);
  const q = (c.req.query("q") ?? "").trim().toLowerCase();

  // We fetch (limit+1) from each source, merge, sort, slice — this gives us
  // correct pagination across two tables without a UNION (D1/Drizzle limitation).
  const fetchSize = limit + offset + 1; // over-fetch to cover offset

  // ── 1. Audit logs (bucket/user CRUD) ────────────────────────────────────

  let auditRows;
  if (q) {
    const pattern = `%${q}%`;
    auditRows = await db
      .select()
      .from(audit_logs)
      .where(
        sql`(
          LOWER(${audit_logs.summary}) LIKE ${pattern}
          OR LOWER(${audit_logs.meta}) LIKE ${pattern}
        )`
      )
      .orderBy(sql`${audit_logs.created_at} DESC`)
      .limit(fetchSize);
  } else {
    auditRows = await db
      .select()
      .from(audit_logs)
      .orderBy(sql`${audit_logs.created_at} DESC`)
      .limit(fetchSize);
  }

  const auditItems: ActivityItem[] = auditRows.map((row) => ({
    id: row.id,
    action: `${row.entity}_${row.action}`, // e.g. "bucket_created", "user_updated"
    actor_id: row.actor_id,
    actor_name: "", // filled below
    summary: row.summary,
    meta: row.meta ? JSON.parse(row.meta) : null,
    created_at: row.created_at,
    source: "audit" as const,
  }));

  // Resolve actor names for audit logs
  const actorIds = [...new Set(auditRows.map((r) => r.actor_id))];
  const actorMap = new Map<string, string>();
  for (const actorId of actorIds) {
    const user = (
      await db
        .select({ full_name: users.full_name })
        .from(users)
        .where(eq(users.id, actorId))
        .limit(1)
    )[0];
    actorMap.set(actorId, user?.full_name ?? "Unknown");
  }
  for (const item of auditItems) {
    item.actor_name = actorMap.get(item.actor_id) ?? "Unknown";
  }

  // ── 2. Transactions (checkout / return) ─────────────────────────────────

  // Fetch recent transactions with actor name
  let txRows;
  if (q) {
    const pattern = `%${q}%`;
    txRows = await db
      .select({
        id: transactions.id,
        type: transactions.type,
        user_id: transactions.user_id,
        performed_by: transactions.performed_by,
        created_at: transactions.created_at,
        user_name: sql<string>`(SELECT full_name FROM users WHERE id = ${transactions.user_id})`,
        performer_name: sql<string>`(SELECT full_name FROM users WHERE id = ${transactions.performed_by})`,
      })
      .from(transactions)
      .where(
        sql`(
          LOWER((SELECT full_name FROM users WHERE id = ${transactions.user_id})) LIKE ${pattern}
          OR LOWER(${transactions.type}) LIKE ${pattern}
        )`
      )
      .orderBy(sql`${transactions.created_at} DESC`)
      .limit(fetchSize);
  } else {
    txRows = await db
      .select({
        id: transactions.id,
        type: transactions.type,
        user_id: transactions.user_id,
        performed_by: transactions.performed_by,
        created_at: transactions.created_at,
        user_name: sql<string>`(SELECT full_name FROM users WHERE id = ${transactions.user_id})`,
        performer_name: sql<string>`(SELECT full_name FROM users WHERE id = ${transactions.performed_by})`,
      })
      .from(transactions)
      .orderBy(sql`${transactions.created_at} DESC`)
      .limit(fetchSize);
  }

  // For each transaction, fetch its line items
  const txItems: ActivityItem[] = await Promise.all(
    txRows.map(async (tx) => {
      const lines = await db
        .select({
          quantity: transaction_items.quantity,
          direction: transaction_items.direction,
          item_name: sql<string>`COALESCE(${item_types.name}, 'Deleted item')`,
          item_emoji: sql<string>`COALESCE(${item_types.emoji}, '📦')`,
          bucket_name: sql<string>`COALESCE(${buckets.name}, 'Deleted bucket')`,
          bucket_barcode: sql<string>`COALESCE(${buckets.barcode}, '')`,
        })
        .from(transaction_items)
        .leftJoin(item_types, eq(transaction_items.item_type_id, item_types.id))
        .leftJoin(buckets, eq(transaction_items.bucket_id, buckets.id))
        .where(eq(transaction_items.transaction_id, tx.id));

      const totalQty = lines.reduce((s, l) => s + l.quantity, 0);
      const actionWord = tx.type === "checkout" ? "checked out" : "returned";

      // The actor is whoever performed the action. If performed_by exists
      // (admin acting on behalf of a scout), use the performer as actor
      // and mention the scout in the summary. Otherwise the user is the actor.
      const actorName = tx.performer_name ?? tx.user_name ?? "Unknown";
      const isOnBehalf = tx.performed_by && tx.performed_by !== tx.user_id;

      let summary: string;
      if (isOnBehalf) {
        summary = `${actionWord} ${totalQty} ${totalQty === 1 ? "item" : "items"} for ${tx.user_name ?? "someone"}`;
      } else {
        summary = `${actionWord} ${totalQty} ${totalQty === 1 ? "item" : "items"}`;
      }

      return {
        id: tx.id,
        action: tx.type, // "checkout" | "return"
        actor_id: tx.performed_by ?? tx.user_id,
        actor_name: actorName,
        summary,
        meta: {
          transaction_id: tx.id,
          user_id: tx.user_id,
          user_name: tx.user_name,
          item_count: totalQty,
          items: lines.map((l) => ({
            quantity: l.quantity,
            item_name: l.item_name,
            item_emoji: l.item_emoji,
            bucket_name: l.bucket_name,
            bucket_barcode: l.bucket_barcode,
          })),
        },
        created_at: tx.created_at,
        source: "transaction" as const,
      };
    })
  );

  // ── 3. Merge, sort, paginate ────────────────────────────────────────────

  const merged = [...auditItems, ...txItems];
  merged.sort((a, b) => b.created_at.localeCompare(a.created_at));

  const sliced = merged.slice(offset, offset + limit + 1);
  const hasMore = sliced.length > limit;
  const data = sliced.slice(0, limit);

  return c.json({
    data,
    has_more: hasMore,
    offset,
    limit,
  });
});

export { activityRoutes };