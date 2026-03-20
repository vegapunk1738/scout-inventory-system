import { Hono } from "hono";
import { sql, eq } from "drizzle-orm";
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
  action: string;
  actor_id: string;
  actor_name: string;
  summary: string;
  meta: Record<string, unknown> | null;
  created_at: string;
  source: "audit" | "transaction";
}

// ─── Filter categories ──────────────────────────────────────────────────────
// ?filter=items     → checkout/return (self-service, not resolves)
// ?filter=resolves  → admin-resolved returns (performed_by ≠ user_id)
// ?filter=buckets   → audit_logs where entity = 'bucket'
// ?filter=users     → audit_logs where entity = 'user'
// (no filter)       → everything

type FilterCategory = "items" | "resolves" | "buckets" | "users" | null;

function parseFilter(raw: string | undefined): FilterCategory {
  if (raw === "items" || raw === "resolves" || raw === "buckets" || raw === "users") {
    return raw;
  }
  return null;
}

// ─── GET /activity ──────────────────────────────────────────────────────────

activityRoutes.get("/", async (c) => {
  const db = c.get("db");

  const offset = Math.max(0, parseInt(c.req.query("offset") ?? "0", 10) || 0);
  const limit = Math.min(parseInt(c.req.query("limit") ?? "20", 10) || 20, 50);
  const q = (c.req.query("q") ?? "").trim().toLowerCase();
  const filter = parseFilter(c.req.query("filter"));

  const fetchSize = limit + offset + 1;

  // Decide which sources to query based on filter
  const includeAudit = filter === null || filter === "buckets" || filter === "users";
  const includeTransactions = filter === null || filter === "items" || filter === "resolves";

  // ── 1. Audit logs (bucket/user CRUD, item resolves) ───────────────────

  let auditItems: ActivityItem[] = [];

  if (includeAudit) {
    // Build entity filter
    let entityFilter = "";
    if (filter === "buckets") entityFilter = `AND ${audit_logs.entity.name} = 'bucket'`;
    else if (filter === "users") entityFilter = `AND ${audit_logs.entity.name} = 'user'`;

    let auditRows;
    if (q) {
      const pattern = `%${q}%`;
      auditRows = await db
        .select()
        .from(audit_logs)
        .where(
          filter === "buckets"
            ? sql`${audit_logs.entity} = 'bucket' AND (LOWER(${audit_logs.summary}) LIKE ${pattern} OR LOWER(${audit_logs.meta}) LIKE ${pattern})`
            : filter === "users"
            ? sql`${audit_logs.entity} = 'user' AND (LOWER(${audit_logs.summary}) LIKE ${pattern} OR LOWER(${audit_logs.meta}) LIKE ${pattern})`
            : sql`(LOWER(${audit_logs.summary}) LIKE ${pattern} OR LOWER(${audit_logs.meta}) LIKE ${pattern})`
        )
        .orderBy(sql`${audit_logs.created_at} DESC`)
        .limit(fetchSize);
    } else {
      auditRows = await db
        .select()
        .from(audit_logs)
        .where(
          filter === "buckets"
            ? sql`${audit_logs.entity} = 'bucket'`
            : filter === "users"
            ? sql`${audit_logs.entity} = 'user'`
            : sql`1=1`
        )
        .orderBy(sql`${audit_logs.created_at} DESC`)
        .limit(fetchSize);
    }

    auditItems = auditRows.map((row) => ({
      id: row.id,
      action: `${row.entity}_${row.action}`,
      actor_id: row.actor_id,
      actor_name: "",
      summary: row.summary,
      meta: row.meta ? JSON.parse(row.meta) : null,
      created_at: row.created_at,
      source: "audit" as const,
    }));

    // Resolve actor names
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
  }

  // ── 2. Transactions (checkout / return / resolve) ─────────────────────

  let txItems: ActivityItem[] = [];

  if (includeTransactions) {
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

    // Build activity items from transactions
    const allTxItems: ActivityItem[] = await Promise.all(
      txRows.map(async (tx) => {
        const lines = await db
          .select({
            quantity: transaction_items.quantity,
            direction: transaction_items.direction,
            status: transaction_items.status,
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

        // Detect resolves: admin (performed_by) acting on behalf of scout (user_id)
        const isResolve = tx.performed_by != null && tx.performed_by !== tx.user_id;

        if (isResolve) {
          // ── Resolve ──
          const actorName = tx.performer_name ?? "Unknown";
          const scoutName = tx.user_name ?? "someone";
          const summary = `resolved for ${scoutName} — ${totalQty} ${totalQty === 1 ? "item" : "items"}`;

          return {
            id: tx.id,
            action: "resolve",
            actor_id: tx.performed_by!,
            actor_name: actorName,
            summary,
            meta: {
              transaction_id: tx.id,
              user_id: tx.user_id,
              user_name: scoutName,
              item_count: totalQty,
              items: lines.map((l) => ({
                quantity: l.quantity,
                status: l.status,
                item_name: l.item_name,
                item_emoji: l.item_emoji,
                bucket_name: l.bucket_name,
                bucket_barcode: l.bucket_barcode,
              })),
            },
            created_at: tx.created_at,
            source: "transaction" as const,
          };
        } else {
          // ── Regular checkout / return ──
          const actionWord = tx.type === "checkout" ? "checked out" : "returned";
          const actorName = tx.user_name ?? "Unknown";
          const summary = `${actionWord} ${totalQty} ${totalQty === 1 ? "item" : "items"}`;

          return {
            id: tx.id,
            action: tx.type,
            actor_id: tx.user_id,
            actor_name: actorName,
            summary,
            meta: {
              transaction_id: tx.id,
              user_id: tx.user_id,
              user_name: tx.user_name,
              item_count: totalQty,
              items: lines.map((l) => ({
                quantity: l.quantity,
                status: l.status,
                item_name: l.item_name,
                item_emoji: l.item_emoji,
                bucket_name: l.bucket_name,
                bucket_barcode: l.bucket_barcode,
              })),
            },
            created_at: tx.created_at,
            source: "transaction" as const,
          };
        }
      })
    );

    // Apply filter: items = non-resolve transactions, resolves = resolve transactions
    if (filter === "items") {
      txItems = allTxItems.filter((t) => t.action !== "resolve");
    } else if (filter === "resolves") {
      txItems = allTxItems.filter((t) => t.action === "resolve");
    } else {
      txItems = allTxItems;
    }
  }

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