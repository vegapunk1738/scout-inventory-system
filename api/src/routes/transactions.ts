import { Hono } from "hono";
import { z } from "zod";
import { eq, and, sql } from "drizzle-orm";
import { Env } from "../types";
import {
  transactions,
  transaction_items,
  item_types,
  buckets,
  users,
} from "../db/schema";
import {
  NotFoundError,
  ConflictError,
  ForbiddenError,
} from "../lib/errors";
import { auth, requireRole } from "../middleware/auth";

// ─── Validation schemas ─────────────────────────────────────────────────────

const CheckoutBody = z.object({
  idempotency_key: z.string().uuid(),
  items: z
    .array(
      z.object({
        bucket_id: z.string().uuid(),
        item_type_id: z.string().uuid(),
        quantity: z.number().int().positive("Quantity must be positive"),
      })
    )
    .min(1, "At least one item is required"),
});

const ReturnBody = z.object({
  idempotency_key: z.string().uuid(),
  items: z
    .array(
      z.object({
        bucket_id: z.string().uuid(),
        item_type_id: z.string().uuid(),
        quantity: z.number().int().positive("Quantity must be positive"),
      })
    )
    .min(1, "At least one item is required"),
});

// ─── Helpers ────────────────────────────────────────────────────────────────

/**
 * For a given item_type, compute how many are currently available.
 * available = item.quantity + SUM(direction * quantity)
 * direction = -1 for checkout (decreases), +1 for return (increases)
 */
async function getAvailableCount(
  db: Env["Variables"]["db"],
  itemTypeId: string
): Promise<{ total: number; available: number; borrowed: number }> {
  const item = (
    await db
      .select()
      .from(item_types)
      .where(eq(item_types.id, itemTypeId))
      .limit(1)
  )[0];

  if (!item) return { total: 0, available: 0, borrowed: 0 };

  const result = await db
    .select({
      net: sql<number>`COALESCE(SUM(${transaction_items.direction} * ${transaction_items.quantity}), 0)`,
    })
    .from(transaction_items)
    .where(eq(transaction_items.item_type_id, itemTypeId));

  const net = result[0]?.net ?? 0;
  const borrowed = Math.max(0, -net);
  const available = Math.max(0, item.quantity + net);

  return { total: item.quantity, available, borrowed };
}

/**
 * Get per-user borrowed count for a specific item_type and user.
 */
async function getUserBorrowedCount(
  db: Env["Variables"]["db"],
  userId: string,
  itemTypeId: string
): Promise<number> {
  const result = await db
    .select({
      borrowed: sql<number>`
        COALESCE(
          SUM(CASE WHEN ${transaction_items.direction} = -1 THEN ${transaction_items.quantity} ELSE 0 END)
          -
          SUM(CASE WHEN ${transaction_items.direction} = 1 THEN ${transaction_items.quantity} ELSE 0 END)
        , 0)`,
    })
    .from(transaction_items)
    .innerJoin(
      transactions,
      eq(transaction_items.transaction_id, transactions.id)
    )
    .where(
      and(
        eq(transaction_items.item_type_id, itemTypeId),
        eq(transactions.user_id, userId)
      )
    );

  return Math.max(0, result[0]?.borrowed ?? 0);
}

/**
 * Validate that all referenced buckets and item_types exist.
 * Returns a map of item_type_id → { itemName, bucketName } for error messages.
 * Throws NotFoundError if any entity is missing.
 */
async function validateEntitiesExist(
  db: Env["Variables"]["db"],
  items: Array<{ bucket_id: string; item_type_id: string }>
): Promise<Map<string, { itemName: string; bucketName: string }>> {
  const info = new Map<string, { itemName: string; bucketName: string }>();

  // Deduplicate IDs
  const uniqueBucketIds = [...new Set(items.map((i) => i.bucket_id))];
  const uniqueItemTypeIds = [...new Set(items.map((i) => i.item_type_id))];

  // Validate buckets exist
  for (const bucketId of uniqueBucketIds) {
    const bucket = (
      await db
        .select({ id: buckets.id, name: buckets.name })
        .from(buckets)
        .where(eq(buckets.id, bucketId))
        .limit(1)
    )[0];

    if (!bucket) {
      throw new NotFoundError(`Bucket (${bucketId})`);
    }
  }

  // Validate item_types exist and belong to their declared bucket
  for (const item of items) {
    const itemType = (
      await db
        .select({
          id: item_types.id,
          name: item_types.name,
          bucket_id: item_types.bucket_id,
        })
        .from(item_types)
        .where(eq(item_types.id, item.item_type_id))
        .limit(1)
    )[0];

    if (!itemType) {
      throw new NotFoundError(`Item type (${item.item_type_id})`);
    }

    if (itemType.bucket_id !== item.bucket_id) {
      throw new ConflictError(
        `Item "${itemType.name}" does not belong to the specified bucket`
      );
    }

    // Look up bucket name for error messages
    const bucket = (
      await db
        .select({ name: buckets.name })
        .from(buckets)
        .where(eq(buckets.id, item.bucket_id))
        .limit(1)
    )[0];

    info.set(item.item_type_id, {
      itemName: itemType.name,
      bucketName: bucket?.name ?? "Unknown bucket",
    });
  }

  return info;
}

// ─── Routes ─────────────────────────────────────────────────────────────────

const transactionRoutes = new Hono<Env>();

transactionRoutes.use("/*", auth());

// ─── POST /transactions/checkout — borrow items ────────────────────────────

transactionRoutes.post("/checkout", async (c) => {
  const body = CheckoutBody.parse(await c.req.json());
  const db = c.get("db");
  const d1 = c.env.DB;
  const jwt = c.get("jwtPayload");

  // ── Step 1: Idempotency check ──────────────────────────────────────────
  const existingTx = (
    await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(eq(transactions.idempotency_key, body.idempotency_key))
      .limit(1)
  )[0];

  if (existingTx) {
    return c.json({
      data: { transaction_id: existingTx.id, idempotent: true },
    });
  }

  // ── Step 2: Validate all entities exist ────────────────────────────────
  const entityInfo = await validateEntitiesExist(db, body.items);

  // ── Step 3: Pre-check availability (fast rejection) ────────────────────
  for (const item of body.items) {
    const { available } = await getAvailableCount(db, item.item_type_id);
    if (item.quantity > available) {
      const info = entityInfo.get(item.item_type_id);
      throw new ConflictError(
        `Not enough "${info?.itemName ?? "item"}" available — requested ${item.quantity}, only ${available} in stock`
      );
    }
  }

  // ── Step 4: Atomic insert via D1 batch ─────────────────────────────────
  // D1 batch = single SQLite transaction = serialized writes = no race
  const txId = crypto.randomUUID();
  const now = new Date().toISOString();

  const statements: D1PreparedStatement[] = [];

  // Insert transaction header
  statements.push(
    d1.prepare(
      `INSERT INTO transactions (id, type, user_id, performed_by, created_at, idempotency_key) VALUES (?1, 'checkout', ?2, ?2, ?3, ?4)`
    ).bind(txId, jwt.sub, now, body.idempotency_key)
  );

  // Insert each transaction item
  for (const item of body.items) {
    statements.push(
      d1.prepare(
        `INSERT INTO transaction_items (id, transaction_id, bucket_id, item_type_id, quantity, direction, status) VALUES (?1, ?2, ?3, ?4, ?5, -1, 'normal')`
      ).bind(
        crypto.randomUUID(),
        txId,
        item.bucket_id,
        item.item_type_id,
        item.quantity
      )
    );
  }

  // Post-insert availability checks (within same transaction)
  // This catches race conditions: if another request sneaked in between
  // our pre-check and our insert, the post-check will detect negative inventory.
  for (const item of body.items) {
    statements.push(
      d1.prepare(
        `SELECT
          it.quantity + COALESCE(
            (SELECT SUM(ti.direction * ti.quantity) FROM transaction_items ti WHERE ti.item_type_id = ?1),
            0
          ) as available,
          it.name
        FROM item_types it
        WHERE it.id = ?1`
      ).bind(item.item_type_id)
    );
  }

  const results = await d1.batch(statements);

  // ── Step 5: Verify no inventory went negative ──────────────────────────
  // The post-check results are at the end of the batch results array.
  // Index: 1 (txn header) + N (items) + i (check for item i)
  const checkStartIndex = 1 + body.items.length;

  for (let i = 0; i < body.items.length; i++) {
    const checkResult = results[checkStartIndex + i] as D1Result;
    const row = checkResult.results?.[0] as
      | { available: number; name: string }
      | undefined;

    if (row && row.available < 0) {
      // Race condition detected — inventory went negative.
      // The batch already committed, so we need to compensate by inserting
      // a reversal transaction that undoes this checkout.
      const reversalId = crypto.randomUUID();
      const reversalStatements: D1PreparedStatement[] = [
        d1.prepare(
          `INSERT INTO transactions (id, type, user_id, performed_by, created_at, idempotency_key) VALUES (?1, 'return', ?2, ?2, ?3, ?4)`
        ).bind(
          reversalId,
          jwt.sub,
          new Date().toISOString(),
          `reversal-${txId}`
        ),
      ];

      // Reverse ALL items from the original checkout
      for (const item of body.items) {
        reversalStatements.push(
          d1.prepare(
            `INSERT INTO transaction_items (id, transaction_id, bucket_id, item_type_id, quantity, direction, status) VALUES (?1, ?2, ?3, ?4, ?5, 1, 'normal')`
          ).bind(
            crypto.randomUUID(),
            reversalId,
            item.bucket_id,
            item.item_type_id,
            item.quantity
          )
        );
      }

      await d1.batch(reversalStatements);

      const info = entityInfo.get(body.items[i].item_type_id);
      throw new ConflictError(
        `"${info?.itemName ?? "item"}" was just checked out by someone else — please try again`
      );
    }
  }

  return c.json(
    { data: { transaction_id: txId, idempotent: false } },
    201
  );
});

// ─── POST /transactions/return — return items ──────────────────────────────

transactionRoutes.post("/return", async (c) => {
  const body = ReturnBody.parse(await c.req.json());
  const db = c.get("db");
  const d1 = c.env.DB;
  const jwt = c.get("jwtPayload");

  // ── Step 1: Idempotency check ──────────────────────────────────────────
  const existingTx = (
    await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(eq(transactions.idempotency_key, body.idempotency_key))
      .limit(1)
  )[0];

  if (existingTx) {
    return c.json({
      data: { transaction_id: existingTx.id, idempotent: true },
    });
  }

  // ── Step 2: Validate entities exist ────────────────────────────────────
  // For returns, we're more lenient: if a bucket was deleted but the user
  // still has items checked out, they should still be able to return them.
  // We validate item_types exist but allow missing buckets (use the bucket_id
  // from the original checkout).
  for (const item of body.items) {
    // Check item_type exists (it may have been removed from a bucket but
    // should still exist in the DB since we don't hard-delete while borrowed)
    const itemType = (
      await db
        .select({ id: item_types.id, name: item_types.name })
        .from(item_types)
        .where(eq(item_types.id, item.item_type_id))
        .limit(1)
    )[0];

    if (!itemType) {
      // If the item_type was hard-deleted, we still allow the return
      // by checking if the user has any transaction history for it.
      const hasHistory = (
        await db
          .select({ id: transaction_items.id })
          .from(transaction_items)
          .innerJoin(
            transactions,
            eq(transaction_items.transaction_id, transactions.id)
          )
          .where(
            and(
              eq(transactions.user_id, jwt.sub),
              eq(transaction_items.item_type_id, item.item_type_id)
            )
          )
          .limit(1)
      )[0];

      if (!hasHistory) {
        throw new NotFoundError(`Item type (${item.item_type_id})`);
      }
    }
  }

  // ── Step 3: Validate user has enough borrowed to return ────────────────
  for (const item of body.items) {
    const userBorrowed = await getUserBorrowedCount(
      db,
      jwt.sub,
      item.item_type_id
    );

    if (item.quantity > userBorrowed) {
      // Look up item name for a helpful error message
      const itemInfo = (
        await db
          .select({ name: item_types.name })
          .from(item_types)
          .where(eq(item_types.id, item.item_type_id))
          .limit(1)
      )[0];

      throw new ConflictError(
        `Cannot return ${item.quantity} of "${itemInfo?.name ?? "item"}" — only ${userBorrowed} borrowed`
      );
    }
  }

  // ── Step 4: Atomic insert via D1 batch ─────────────────────────────────
  const txId = crypto.randomUUID();
  const now = new Date().toISOString();

  const statements: D1PreparedStatement[] = [];

  statements.push(
    d1.prepare(
      `INSERT INTO transactions (id, type, user_id, performed_by, created_at, idempotency_key) VALUES (?1, 'return', ?2, ?2, ?3, ?4)`
    ).bind(txId, jwt.sub, now, body.idempotency_key)
  );

  for (const item of body.items) {
    statements.push(
      d1.prepare(
        `INSERT INTO transaction_items (id, transaction_id, bucket_id, item_type_id, quantity, direction, status) VALUES (?1, ?2, ?3, ?4, ?5, 1, 'normal')`
      ).bind(
        crypto.randomUUID(),
        txId,
        item.bucket_id,
        item.item_type_id,
        item.quantity
      )
    );
  }

  await d1.batch(statements);

  return c.json(
    { data: { transaction_id: txId, idempotent: false } },
    201
  );
});

// ─── GET /transactions/me — current user's borrowed + returned items ───────

transactionRoutes.get("/me", async (c) => {
  const db = c.get("db");
  const jwt = c.get("jwtPayload");

  // Get all transaction items for this user, grouped by item_type
  // Uses LEFT JOIN so items still show even if bucket/item_type was deleted
  const borrowed = await db
    .select({
      item_type_id: transaction_items.item_type_id,
      bucket_id: transaction_items.bucket_id,
      item_name: sql<string>`COALESCE(${item_types.name}, 'Deleted item')`,
      item_emoji: sql<string>`COALESCE(${item_types.emoji}, '📦')`,
      bucket_name: sql<string>`COALESCE(${buckets.name}, 'Deleted bucket')`,
      bucket_barcode: sql<string>`COALESCE(${buckets.barcode}, '')`,
      item_total_quantity: sql<number>`COALESCE(${item_types.quantity}, 0)`,
      managed_by: sql<string>`COALESCE((SELECT full_name FROM users WHERE id = ${buckets.created_by}), 'Unknown')`,
      borrowed: sql<number>`
        SUM(CASE WHEN ${transaction_items.direction} = -1 THEN ${transaction_items.quantity} ELSE 0 END)
        -
        SUM(CASE WHEN ${transaction_items.direction} = 1 THEN ${transaction_items.quantity} ELSE 0 END)
      `,
    })
    .from(transaction_items)
    .innerJoin(
      transactions,
      eq(transaction_items.transaction_id, transactions.id)
    )
    .leftJoin(item_types, eq(transaction_items.item_type_id, item_types.id))
    .leftJoin(buckets, eq(transaction_items.bucket_id, buckets.id))
    .where(eq(transactions.user_id, jwt.sub))
    .groupBy(transaction_items.item_type_id)
    .having(sql`
      SUM(CASE WHEN ${transaction_items.direction} = -1 THEN ${transaction_items.quantity} ELSE 0 END)
      -
      SUM(CASE WHEN ${transaction_items.direction} = 1 THEN ${transaction_items.quantity} ELSE 0 END)
      > 0
    `);

  // Get recent return history (last 50)
  const returnHistory = await db
    .select({
      transaction_id: transactions.id,
      created_at: transactions.created_at,
      item_type_id: transaction_items.item_type_id,
      bucket_id: transaction_items.bucket_id,
      item_name: sql<string>`COALESCE(${item_types.name}, 'Deleted item')`,
      item_emoji: sql<string>`COALESCE(${item_types.emoji}, '📦')`,
      bucket_name: sql<string>`COALESCE(${buckets.name}, 'Deleted bucket')`,
      bucket_barcode: sql<string>`COALESCE(${buckets.barcode}, '')`,
      managed_by: sql<string>`COALESCE((SELECT full_name FROM users WHERE id = ${buckets.created_by}), 'Unknown')`,
      quantity: transaction_items.quantity,
      status: transaction_items.status,
    })
    .from(transaction_items)
    .innerJoin(
      transactions,
      eq(transaction_items.transaction_id, transactions.id)
    )
    .leftJoin(item_types, eq(transaction_items.item_type_id, item_types.id))
    .leftJoin(buckets, eq(transaction_items.bucket_id, buckets.id))
    .where(
      and(
        eq(transactions.user_id, jwt.sub),
        eq(transaction_items.direction, 1) // returns only
      )
    )
    .orderBy(sql`${transactions.created_at} DESC`)
    .limit(50);

  // Get checkout timestamps per item for borrowed items
  const borrowedWithDates = await Promise.all(
    borrowed.map(async (b) => {
      const lastCheckout = (
        await db
          .select({ created_at: transactions.created_at })
          .from(transaction_items)
          .innerJoin(
            transactions,
            eq(transaction_items.transaction_id, transactions.id)
          )
          .where(
            and(
              eq(transactions.user_id, jwt.sub),
              eq(transaction_items.item_type_id, b.item_type_id),
              eq(transaction_items.direction, -1)
            )
          )
          .orderBy(sql`${transactions.created_at} DESC`)
          .limit(1)
      )[0];

      return {
        item_type_id: b.item_type_id,
        bucket_id: b.bucket_id,
        item_name: b.item_name,
        item_emoji: b.item_emoji,
        bucket_name: b.bucket_name,
        bucket_barcode: b.bucket_barcode,
        managed_by: b.managed_by,
        borrowed: Number(b.borrowed),
        item_total_quantity: b.item_total_quantity,
        checked_out_at: lastCheckout?.created_at ?? null,
      };
    })
  );

  return c.json({
    data: {
      borrowed: borrowedWithDates,
      return_history: returnHistory.map((r) => ({
        transaction_id: r.transaction_id,
        created_at: r.created_at,
        item_type_id: r.item_type_id,
        bucket_id: r.bucket_id,
        item_name: r.item_name,
        item_emoji: r.item_emoji,
        bucket_name: r.bucket_name,
        bucket_barcode: r.bucket_barcode,
        managed_by: r.managed_by,
        quantity: r.quantity,
        status: r.status,
      })),
    },
  });
});

export { transactionRoutes };