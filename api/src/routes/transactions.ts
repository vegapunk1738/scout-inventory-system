import { Hono } from "hono";
import { z } from "zod";
import { eq, and, sql } from "drizzle-orm";
import { Env } from "../types";
import {
  transactions,
  transaction_items,
  item_types,
  buckets,
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
  // net will be negative when more items are checked out than returned
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

// ─── Routes ─────────────────────────────────────────────────────────────────

const transactionRoutes = new Hono<Env>();

transactionRoutes.use("/*", auth());

// ─── POST /transactions/checkout — borrow items ────────────────────────────

transactionRoutes.post("/checkout", async (c) => {
  const body = CheckoutBody.parse(await c.req.json());
  const db = c.get("db");
  const jwt = c.get("jwtPayload");

  // Idempotency check
  const existingTx = (
    await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(eq(transactions.idempotency_key, body.idempotency_key))
      .limit(1)
  )[0];

  if (existingTx) {
    // Already processed — return success (idempotent)
    return c.json({ data: { transaction_id: existingTx.id, idempotent: true } });
  }

  // Validate availability for each item
  for (const item of body.items) {
    const { available } = await getAvailableCount(db, item.item_type_id);
    if (item.quantity > available) {
      const itemInfo = (
        await db
          .select({ name: item_types.name })
          .from(item_types)
          .where(eq(item_types.id, item.item_type_id))
          .limit(1)
      )[0];

      throw new ConflictError(
        `Not enough "${itemInfo?.name ?? "item"}" available — requested ${item.quantity}, only ${available} in stock`
      );
    }
  }

  // Create transaction
  const txId = crypto.randomUUID();
  const now = new Date().toISOString();

  await db.insert(transactions).values({
    id: txId,
    type: "checkout",
    user_id: jwt.sub,
    created_at: now,
    idempotency_key: body.idempotency_key,
  });

  // Create transaction items
  for (const item of body.items) {
    await db.insert(transaction_items).values({
      id: crypto.randomUUID(),
      transaction_id: txId,
      bucket_id: item.bucket_id,
      item_type_id: item.item_type_id,
      quantity: item.quantity,
      direction: -1, // checkout = items leave inventory
      status: "normal",
    });
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
  const jwt = c.get("jwtPayload");

  // Idempotency check
  const existingTx = (
    await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(eq(transactions.idempotency_key, body.idempotency_key))
      .limit(1)
  )[0];

  if (existingTx) {
    return c.json({ data: { transaction_id: existingTx.id, idempotent: true } });
  }

  // Validate: user can't return more than they have borrowed
  for (const item of body.items) {
    const userBorrowed = await getUserBorrowedCount(
      db,
      jwt.sub,
      item.item_type_id
    );
    if (item.quantity > userBorrowed) {
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

  // Create transaction
  const txId = crypto.randomUUID();
  const now = new Date().toISOString();

  await db.insert(transactions).values({
    id: txId,
    type: "return",
    user_id: jwt.sub,
    created_at: now,
    idempotency_key: body.idempotency_key,
  });

  // Create transaction items
  for (const item of body.items) {
    await db.insert(transaction_items).values({
      id: crypto.randomUUID(),
      transaction_id: txId,
      bucket_id: item.bucket_id,
      item_type_id: item.item_type_id,
      quantity: item.quantity,
      direction: 1, // return = items enter inventory
      status: "normal",
    });
  }

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
  const borrowed = await db
    .select({
      item_type_id: transaction_items.item_type_id,
      bucket_id: transaction_items.bucket_id,
      item_name: item_types.name,
      item_emoji: item_types.emoji,
      bucket_name: buckets.name,
      bucket_barcode: buckets.barcode,
      item_total_quantity: item_types.quantity,
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
    .innerJoin(item_types, eq(transaction_items.item_type_id, item_types.id))
    .innerJoin(buckets, eq(transaction_items.bucket_id, buckets.id))
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
      item_name: item_types.name,
      item_emoji: item_types.emoji,
      bucket_name: buckets.name,
      quantity: transaction_items.quantity,
      status: transaction_items.status,
    })
    .from(transaction_items)
    .innerJoin(
      transactions,
      eq(transaction_items.transaction_id, transactions.id)
    )
    .innerJoin(item_types, eq(transaction_items.item_type_id, item_types.id))
    .innerJoin(buckets, eq(transaction_items.bucket_id, buckets.id))
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
      // Get the most recent checkout date for this item
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
        borrowed: Number(b.borrowed),
        item_total_quantity: b.item_total_quantity,
        checked_out_at: lastCheckout?.created_at ?? null,
      };
    })
  );

  return c.json({
    data: {
      borrowed: borrowedWithDates,
      return_history: returnHistory,
    },
  });
});

// ─── GET /transactions/user/:userId — admin view of user's borrowed items ──

transactionRoutes.get(
  "/user/:userId",
  requireRole("admin"),
  async (c) => {
    const userId = c.req.param("userId");
    const db = c.get("db");

    const borrowed = await db
      .select({
        item_type_id: transaction_items.item_type_id,
        bucket_id: transaction_items.bucket_id,
        item_name: item_types.name,
        item_emoji: item_types.emoji,
        bucket_name: buckets.name,
        bucket_barcode: buckets.barcode,
        item_total_quantity: item_types.quantity,
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
      .innerJoin(item_types, eq(transaction_items.item_type_id, item_types.id))
      .innerJoin(buckets, eq(transaction_items.bucket_id, buckets.id))
      .where(eq(transactions.user_id, userId))
      .groupBy(transaction_items.item_type_id)
      .having(sql`
        SUM(CASE WHEN ${transaction_items.direction} = -1 THEN ${transaction_items.quantity} ELSE 0 END)
        -
        SUM(CASE WHEN ${transaction_items.direction} = 1 THEN ${transaction_items.quantity} ELSE 0 END)
        > 0
      `);

    return c.json({
      data: {
        user_id: userId,
        borrowed: borrowed.map((b) => ({
          ...b,
          borrowed: Number(b.borrowed),
        })),
      },
    });
  }
);

export { transactionRoutes };