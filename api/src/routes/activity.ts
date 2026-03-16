import { Hono } from "hono";
import { sql } from "drizzle-orm";
import { Env } from "../types";
import { auth, requireRole } from "../middleware/auth";

// ─── Types ──────────────────────────────────────────────────────────────────

/**
 * Unified activity entry returned by the API.
 *
 * `kind` splits into two families:
 *   - transaction kinds: checkout, return, resolved_lost, resolved_damaged
 *   - audit kinds:       bucket_created, bucket_updated, bucket_deleted,
 *                         user_created, user_updated, user_deleted
 */
type ActivityKind =
  | "checkout"
  | "return"
  | "resolved_lost"
  | "resolved_damaged"
  | "bucket_created"
  | "bucket_updated"
  | "bucket_deleted"
  | "user_created"
  | "user_updated"
  | "user_deleted";

// ─── Routes ─────────────────────────────────────────────────────────────────

const activityRoutes = new Hono<Env>();

activityRoutes.use("/*", auth(), requireRole("admin"));

/**
 * GET /activity
 *
 * Query params:
 *   limit   — page size (default 20, max 100)
 *   offset  — pagination offset (default 0)
 *   since   — ISO timestamp; only return entries created after this
 *   entity  — filter: 'item' | 'bucket' | 'user' | 'all' (default 'all')
 *   action  — filter: 'checkout' | 'return' | 'resolved' | 'created' |
 *             'updated' | 'deleted' | 'all' (default 'all')
 *   q       — search query (matches actor name, summary)
 *
 * Response:
 * {
 *   data: ActivityEntry[],
 *   has_more: boolean,
 *   total: number          // total matching (for the current filters)
 * }
 */
activityRoutes.get("/", async (c) => {
  const d1 = c.env.DB;

  const limit = Math.min(parseInt(c.req.query("limit") ?? "20", 10) || 20, 100);
  const offset = parseInt(c.req.query("offset") ?? "0", 10) || 0;
  const since = c.req.query("since") ?? null;
  const entityFilter = c.req.query("entity") ?? "all";
  const actionFilter = c.req.query("action") ?? "all";
  const searchQuery = (c.req.query("q") ?? "").trim().toLowerCase();

  // ── Build a UNION ALL query over transactions + audit_logs ────────────
  //
  // We normalise both sources into the same shape:
  //   id, kind, actor_id, actor_name, entity, summary, meta, created_at
  //
  // For transactions we join users + aggregate transaction_items into a
  // JSON summary. For audit_logs we join the actor's name.

  const whereClauses: string[] = [];
  const params: unknown[] = [];

  // ── since filter
  if (since) {
    whereClauses.push("a.created_at > ?");
    params.push(since);
  }

  // ── entity filter
  if (entityFilter === "item") {
    whereClauses.push("a.entity = 'item'");
  } else if (entityFilter === "bucket") {
    whereClauses.push("a.entity = 'bucket'");
  } else if (entityFilter === "user") {
    whereClauses.push("a.entity = 'user'");
  }

  // ── action filter
  if (actionFilter === "checkout") {
    whereClauses.push("a.kind = 'checkout'");
  } else if (actionFilter === "return") {
    whereClauses.push("a.kind = 'return'");
  } else if (actionFilter === "resolved") {
    whereClauses.push("a.kind IN ('resolved_lost', 'resolved_damaged')");
  } else if (actionFilter === "created") {
    whereClauses.push("a.kind LIKE '%_created'");
  } else if (actionFilter === "updated") {
    whereClauses.push("a.kind LIKE '%_updated'");
  } else if (actionFilter === "deleted") {
    whereClauses.push("a.kind LIKE '%_deleted'");
  }

  // ── search filter
  if (searchQuery) {
    whereClauses.push("(LOWER(a.actor_name) LIKE ? OR LOWER(a.summary) LIKE ?)");
    params.push(`%${searchQuery}%`, `%${searchQuery}%`);
  }

  const whereSQL = whereClauses.length > 0
    ? "WHERE " + whereClauses.join(" AND ")
    : "";

  // ── The big UNION query ───────────────────────────────────────────────
  //
  // Part 1: Transactions → activity entries
  //   Each transaction becomes one row. We aggregate its line items into
  //   a JSON array stored in `meta`.
  //
  // Part 2: Audit logs → activity entries (already in the right shape)

  const unionSQL = `
    SELECT * FROM (
      -- ── Transactions ──────────────────────────────────────────────
      SELECT
        t.id                                                  AS id,
        CASE
          WHEN t.type = 'checkout' THEN 'checkout'
          WHEN t.type = 'return' AND EXISTS (
            SELECT 1 FROM transaction_items ti2
            WHERE ti2.transaction_id = t.id AND ti2.status IN ('lost','damaged')
          ) THEN 'resolved_' || (
            SELECT ti3.status FROM transaction_items ti3
            WHERE ti3.transaction_id = t.id AND ti3.status IN ('lost','damaged')
            LIMIT 1
          )
          ELSE 'return'
        END                                                   AS kind,
        t.user_id                                             AS actor_id,
        COALESCE(u.full_name, 'Unknown')                      AS actor_name,
        'item'                                                AS entity,
        CASE
          WHEN t.type = 'checkout' THEN
            u.full_name || ' checked out ' ||
            (SELECT COUNT(*) FROM transaction_items ti WHERE ti.transaction_id = t.id) ||
            ' item(s)'
          ELSE
            u.full_name || ' returned ' ||
            (SELECT COUNT(*) FROM transaction_items ti WHERE ti.transaction_id = t.id) ||
            ' item(s)'
        END                                                   AS summary,
        (
          SELECT json_group_array(
            json_object(
              'item_name', COALESCE(it.name, 'Deleted item'),
              'item_emoji', COALESCE(it.emoji, '📦'),
              'bucket_name', COALESCE(b.name, 'Deleted bucket'),
              'bucket_barcode', COALESCE(b.barcode, ''),
              'quantity', ti.quantity,
              'status', ti.status
            )
          )
          FROM transaction_items ti
          LEFT JOIN item_types it ON ti.item_type_id = it.id
          LEFT JOIN buckets b ON ti.bucket_id = b.id
          WHERE ti.transaction_id = t.id
        )                                                     AS meta,
        t.created_at                                          AS created_at
      FROM transactions t
      LEFT JOIN users u ON t.user_id = u.id

      UNION ALL

      -- ── Audit logs ────────────────────────────────────────────────
      SELECT
        al.id                                                 AS id,
        al.entity || '_' || al.action                         AS kind,
        al.actor_id                                           AS actor_id,
        COALESCE(u2.full_name, 'Unknown')                     AS actor_name,
        al.entity                                             AS entity,
        al.summary                                            AS summary,
        al.meta                                               AS meta,
        al.created_at                                         AS created_at
      FROM audit_logs al
      LEFT JOIN users u2 ON al.actor_id = u2.id
    ) a
    ${whereSQL}
    ORDER BY a.created_at DESC
  `;

  // ── Count query ───────────────────────────────────────────────────────
  const countSQL = `SELECT COUNT(*) as total FROM (${unionSQL})`;
  const countResult = await d1.prepare(countSQL).bind(...params).first<{ total: number }>();
  const total = countResult?.total ?? 0;

  // ── Data query with pagination ────────────────────────────────────────
  const dataSQL = `${unionSQL} LIMIT ? OFFSET ?`;
  const dataResult = await d1
    .prepare(dataSQL)
    .bind(...params, limit, offset)
    .all();

  const rows = (dataResult.results ?? []).map((row: any) => ({
    id: row.id,
    kind: row.kind,
    actor_id: row.actor_id,
    actor_name: row.actor_name,
    entity: row.entity,
    summary: row.summary,
    meta: row.meta ? tryParseJSON(row.meta) : null,
    created_at: row.created_at,
  }));

  return c.json({
    data: rows,
    has_more: offset + limit < total,
    total,
  });
});

/**
 * GET /activity/poll
 *
 * Lightweight endpoint for polling. Returns only the count of new entries
 * since a given timestamp, plus the latest entry's timestamp.
 *
 * Query params:
 *   since — ISO timestamp (required)
 *
 * Response:
 * {
 *   new_count: number,
 *   latest_at: string | null
 * }
 */
activityRoutes.get("/poll", async (c) => {
  const d1 = c.env.DB;
  const since = c.req.query("since");

  if (!since) {
    return c.json({ error: "Missing 'since' parameter" }, 400);
  }

  const countSQL = `
    SELECT COUNT(*) as cnt FROM (
      SELECT created_at FROM transactions WHERE created_at > ?1
      UNION ALL
      SELECT created_at FROM audit_logs WHERE created_at > ?1
    )
  `;

  const latestSQL = `
    SELECT MAX(created_at) as latest_at FROM (
      SELECT created_at FROM transactions WHERE created_at > ?1
      UNION ALL
      SELECT created_at FROM audit_logs WHERE created_at > ?1
    )
  `;

  const [countRes, latestRes] = await Promise.all([
    d1.prepare(countSQL).bind(since).first<{ cnt: number }>(),
    d1.prepare(latestSQL).bind(since).first<{ latest_at: string | null }>(),
  ]);

  return c.json({
    new_count: countRes?.cnt ?? 0,
    latest_at: latestRes?.latest_at ?? null,
  });
});

function tryParseJSON(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

export { activityRoutes };