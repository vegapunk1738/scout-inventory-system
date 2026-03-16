import { Hono } from "hono";
import { z } from "zod";
import { eq, and, sql } from "drizzle-orm";
import { Env } from "../types";
import { buckets, item_types, transaction_items, transactions, users } from "../db/schema";
import { NotFoundError, ConflictError, ForbiddenError } from "../lib/errors";
import { auth, requireRole } from "../middleware/auth";

// ─── Validation schemas ─────────────────────────────────────────────────────

const CreateBucketBody = z.object({
  name: z.string().min(2, "Name must be at least 2 characters").max(100).trim(),
  abbreviation: z
    .string()
    .regex(/^[A-Z]{3}$/, "Abbreviation must be exactly 3 uppercase letters"),
  items: z
    .array(
      z.object({
        name: z.string().min(1, "Item name is required").max(48).trim(),
        emoji: z.string().min(1).max(8).default("📦"),
        quantity: z.number().int().min(1, "Quantity must be at least 1").max(999),
      })
    )
    .default([]),
});

const UpdateBucketBody = z.object({
  name: z
    .string()
    .min(2, "Name must be at least 2 characters")
    .max(100)
    .trim()
    .optional(),
  items: z
    .array(
      z.object({
        id: z.string().uuid().optional(), // existing item → update; absent → create
        name: z.string().min(1, "Item name is required").max(48).trim(),
        emoji: z.string().min(1).max(8).default("📦"),
        quantity: z.number().int().min(1, "Quantity must be at least 1").max(999),
      })
    )
    .optional(),
});

const ResolveBorrowedBody = z.object({
  resolutions: z.array(
    z.object({
      user_id: z.string().min(1),  // not .uuid() — seed users have non-v4 UUIDs
      quantity: z.number().int().min(1),
      status: z.enum(["returned", "lost", "damaged"]),
    })
  ),
});

// ─── Helpers ────────────────────────────────────────────────────────────────

async function generateUniqueBarcode(
  db: Env["Variables"]["db"],
  abbreviation: string
): Promise<string> {
  const maxAttempts = 10;

  for (let i = 0; i < maxAttempts; i++) {
    const random = Math.floor(Math.random() * 1000)
      .toString()
      .padStart(3, "0");
    const barcode = `SSB-${abbreviation}-${random}`;

    const existing = (
      await db
        .select({ id: buckets.id })
        .from(buckets)
        .where(eq(buckets.barcode, barcode))
        .limit(1)
    )[0];

    if (!existing) return barcode;
  }

  throw new ConflictError(
    "Could not generate a unique barcode. Try a different abbreviation."
  );
}

/**
 * For a given item_type, compute how many are currently borrowed (checked out
 * but not yet returned) across all users.
 */
async function getBorrowedCount(
  db: Env["Variables"]["db"],
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
    .where(eq(transaction_items.item_type_id, itemTypeId));

  const val = result[0]?.borrowed ?? 0;
  return Math.max(0, val);
}

/**
 * Returns per-user breakdown of who has borrowed items for a given item_type.
 */
async function getBorrowedByUser(
  db: Env["Variables"]["db"],
  itemTypeId: string
): Promise<Array<{ user_id: string; full_name: string; scout_id: string; borrowed: number }>> {
  const rows = await db
    .select({
      user_id: transactions.user_id,
      full_name: users.full_name,
      scout_id: users.scout_id,
      borrowed: sql<number>`
        SUM(CASE WHEN ${transaction_items.direction} = -1 THEN ${transaction_items.quantity} ELSE 0 END)
        -
        SUM(CASE WHEN ${transaction_items.direction} = 1 THEN ${transaction_items.quantity} ELSE 0 END)
      `,
    })
    .from(transaction_items)
    .innerJoin(transactions, eq(transaction_items.transaction_id, transactions.id))
    .innerJoin(users, eq(transactions.user_id, users.id))
    .where(eq(transaction_items.item_type_id, itemTypeId))
    .groupBy(transactions.user_id)
    .having(sql`
      SUM(CASE WHEN ${transaction_items.direction} = -1 THEN ${transaction_items.quantity} ELSE 0 END)
      -
      SUM(CASE WHEN ${transaction_items.direction} = 1 THEN ${transaction_items.quantity} ELSE 0 END)
      > 0
    `);

  return rows.map((r) => ({
    user_id: r.user_id,
    full_name: r.full_name,
    scout_id: r.scout_id,
    borrowed: Number(r.borrowed),
  }));
}

// ─── Routes ─────────────────────────────────────────────────────────────────

const bucketRoutes = new Hono<Env>();

// All bucket routes require authentication
bucketRoutes.use("/*", auth());

// ─── GET /buckets — list all buckets with item counts + stock state ─────────

bucketRoutes.get("/", async (c) => {
  const db = c.get("db");

  const allBuckets = await db.select().from(buckets).all();

  const result = await Promise.all(
    allBuckets.map(async (bucket) => {
      const items = await db
        .select()
        .from(item_types)
        .where(eq(item_types.bucket_id, bucket.id));

      // Compute borrowed counts for each item
      const itemsWithAvailable = await Promise.all(
        items.map(async (item) => {
          const borrowed = await getBorrowedCount(db, item.id);
          return {
            id: item.id,
            name: item.name,
            emoji: item.emoji,
            quantity: item.quantity,
            borrowed,
            available: Math.max(0, item.quantity - borrowed),
          };
        })
      );

      // Determine stock state
      const totalStock = itemsWithAvailable.reduce((s, i) => s + i.quantity, 0);
      const totalAvailable = itemsWithAvailable.reduce((s, i) => s + i.available, 0);

      let stock_state: "fully_stocked" | "in_use" | "out_of_stock";
      if (totalStock === 0 || items.length === 0) {
        stock_state = "out_of_stock";
      } else if (totalAvailable < totalStock) {
        stock_state = "in_use";
      } else {
        stock_state = "fully_stocked";
      }

      const creator = (
        await db
          .select({ full_name: users.full_name })
          .from(users)
          .where(eq(users.id, bucket.created_by))
          .limit(1)
      )[0];

      return {
        id: bucket.id,
        name: bucket.name,
        barcode: bucket.barcode,
        created_at: bucket.created_at,
        created_by: bucket.created_by,
        created_by_name: creator?.full_name ?? "Unknown",
        item_type_count: items.length,
        stock_state,
        items: itemsWithAvailable,
      };
    })
  );

  // Sort by most recently created
  result.sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );

  return c.json({ data: result });
});

// ─── GET /buckets/barcode/:barcode — scan lookup ────────────────────────────

bucketRoutes.get("/barcode/:barcode", async (c) => {
  const barcode = c.req.param("barcode");
  const db = c.get("db");

  const bucket = (
    await db
      .select()
      .from(buckets)
      .where(eq(buckets.barcode, barcode))
      .limit(1)
  )[0];

  if (!bucket) throw new NotFoundError("Bucket");

  const items = await db
    .select()
    .from(item_types)
    .where(eq(item_types.bucket_id, bucket.id));

  const itemsWithAvailable = await Promise.all(
    items.map(async (item) => {
      const borrowed = await getBorrowedCount(db, item.id);
      return {
        id: item.id,
        name: item.name,
        emoji: item.emoji,
        quantity: item.quantity,
        borrowed,
        available: Math.max(0, item.quantity - borrowed),
      };
    })
  );

  return c.json({
    data: {
      ...bucket,
      items: itemsWithAvailable,
    },
  });
});

// ─── GET /buckets/:id — single bucket detail ───────────────────────────────

bucketRoutes.get("/:id", async (c) => {
  const id = c.req.param("id");
  const db = c.get("db");

  const bucket = (
    await db.select().from(buckets).where(eq(buckets.id, id)).limit(1)
  )[0];

  if (!bucket) throw new NotFoundError("Bucket");

  const items = await db
    .select()
    .from(item_types)
    .where(eq(item_types.bucket_id, bucket.id));

  const itemsWithAvailable = await Promise.all(
    items.map(async (item) => {
      const borrowed = await getBorrowedCount(db, item.id);
      return {
        id: item.id,
        name: item.name,
        emoji: item.emoji,
        quantity: item.quantity,
        borrowed,
        available: Math.max(0, item.quantity - borrowed),
      };
    })
  );

  return c.json({
    data: {
      ...bucket,
      items: itemsWithAvailable,
    },
  });
});

// ─── POST /buckets — create bucket (admin only) ────────────────────────────

bucketRoutes.post("/", requireRole("admin"), async (c) => {
  const body = CreateBucketBody.parse(await c.req.json());
  const db = c.get("db");
  const jwt = c.get("jwtPayload");

  // Generate unique barcode
  const barcode = await generateUniqueBarcode(db, body.abbreviation);

  const bucketId = crypto.randomUUID();
  const now = new Date().toISOString();

  // Insert bucket
  const inserted = (
    await db
      .insert(buckets)
      .values({
        id: bucketId,
        name: body.name,
        barcode,
        created_at: now,
        created_by: jwt.sub,
      })
      .returning()
  )[0];

  // Insert items
  const insertedItems = [];
  for (const item of body.items) {
    const itemRow = (
      await db
        .insert(item_types)
        .values({
          id: crypto.randomUUID(),
          name: item.name,
          emoji: item.emoji,
          bucket_id: bucketId,
          quantity: item.quantity,
        })
        .returning()
    )[0];
    insertedItems.push({
      ...itemRow,
      borrowed: 0,
      available: itemRow.quantity,
    });
  }

  return c.json(
    {
      data: {
        ...inserted,
        items: insertedItems,
      },
    },
    201
  );
});

// ─── PATCH /buckets/:id — update bucket (admin only) ───────────────────────

bucketRoutes.patch("/:id", requireRole("admin"), async (c) => {
  const id = c.req.param("id");
  const body = UpdateBucketBody.parse(await c.req.json());
  const db = c.get("db");

  const existing = (
    await db.select().from(buckets).where(eq(buckets.id, id)).limit(1)
  )[0];
  if (!existing) throw new NotFoundError("Bucket");

  // Update bucket name if provided
  if (body.name) {
    await db.update(buckets).set({ name: body.name }).where(eq(buckets.id, id));
  }

  // Update items if provided
  if (body.items) {
    const existingItems = await db
      .select()
      .from(item_types)
      .where(eq(item_types.bucket_id, id));

    const existingIds = new Set(existingItems.map((i) => i.id));
    const incomingIds = new Set(
      body.items.filter((i) => i.id).map((i) => i.id!)
    );

    // Delete items that are no longer in the list
    for (const existing of existingItems) {
      if (!incomingIds.has(existing.id)) {
        // Check if any are borrowed before deleting
        const borrowed = await getBorrowedCount(db, existing.id);
        if (borrowed > 0) {
          // Return 409 with borrower details so frontend can show resolution sheet
          const borrowers = await getBorrowedByUser(db, existing.id);
          return c.json(
            {
              error: "item_has_borrowed",
              message: `Cannot delete "${existing.name}" — ${borrowed} currently borrowed`,
              item_type_id: existing.id,
              item_name: existing.name,
              item_emoji: existing.emoji,
              currently_borrowed: borrowed,
              borrowers: borrowers.filter((b) => b.borrowed > 0),
            },
            409
          );
        }
        // Soft-delete: detach from bucket so item name stays for transaction history
        await db
          .update(item_types)
          .set({ bucket_id: "__deleted__" })
          .where(eq(item_types.id, existing.id));
      }
    }

    // Upsert items
    for (const item of body.items) {
      if (item.id && existingIds.has(item.id)) {
        // Update existing item
        const currentItem = existingItems.find((e) => e.id === item.id)!;

        // Check quantity decrease constraint
        if (item.quantity < currentItem.quantity) {
          const borrowed = await getBorrowedCount(db, item.id);
          if (item.quantity < borrowed) {
            // Return 409 with borrowed details so frontend can show resolution sheet
            const borrowers = await getBorrowedByUser(db, item.id);
            return c.json(
              {
                error: "quantity_conflict",
                message: `Cannot decrease "${currentItem.name}" to ${item.quantity} — ${borrowed} currently borrowed`,
                item_type_id: item.id,
                item_name: currentItem.name,
                requested_quantity: item.quantity,
                currently_borrowed: borrowed,
                borrowers,
              },
              409
            );
          }
        }

        await db
          .update(item_types)
          .set({
            name: item.name,
            emoji: item.emoji,
            quantity: item.quantity,
          })
          .where(eq(item_types.id, item.id));
      } else {
        // Create new item
        await db.insert(item_types).values({
          id: crypto.randomUUID(),
          name: item.name,
          emoji: item.emoji,
          bucket_id: id,
          quantity: item.quantity,
        });
      }
    }
  }

  // Re-fetch the full bucket with items
  const updated = (
    await db.select().from(buckets).where(eq(buckets.id, id)).limit(1)
  )[0];

  const items = await db
    .select()
    .from(item_types)
    .where(eq(item_types.bucket_id, id));

  const itemsWithAvailable = await Promise.all(
    items.map(async (item) => {
      const borrowed = await getBorrowedCount(db, item.id);
      return {
        ...item,
        borrowed,
        available: Math.max(0, item.quantity - borrowed),
      };
    })
  );

  return c.json({
    data: {
      ...updated,
      items: itemsWithAvailable,
    },
  });
});

// ─── GET /buckets/:id/items/:itemId/borrowers — who has this item ──────────

bucketRoutes.get(
  "/:id/items/:itemId/borrowers",
  requireRole("admin"),
  async (c) => {
    const itemId = c.req.param("itemId");
    const db = c.get("db");

    const item = (
      await db
        .select()
        .from(item_types)
        .where(eq(item_types.id, itemId))
        .limit(1)
    )[0];

    if (!item) throw new NotFoundError("Item");

    const borrowers = await getBorrowedByUser(db, itemId);

    return c.json({
      data: {
        item_type_id: itemId,
        item_name: item.name,
        total_quantity: item.quantity,
        total_borrowed: borrowers.reduce((s, b) => s + b.borrowed, 0),
        borrowers,
      },
    });
  }
);

// ─── POST /buckets/:id/items/:itemId/resolve — resolve borrowed items ──────

bucketRoutes.post(
  "/:id/items/:itemId/resolve",
  requireRole("admin"),
  async (c) => {
    const bucketId = c.req.param("id");
    const itemId = c.req.param("itemId");
    const body = ResolveBorrowedBody.parse(await c.req.json());
    const db = c.get("db");
    const jwt = c.get("jwtPayload");

    const item = (
      await db
        .select()
        .from(item_types)
        .where(
          and(eq(item_types.id, itemId), eq(item_types.bucket_id, bucketId))
        )
        .limit(1)
    )[0];

    if (!item) throw new NotFoundError("Item");

    const now = new Date().toISOString();
    const resolvedTransactions = [];

    for (const resolution of body.resolutions) {
      // Verify user actually has this many borrowed
      const borrowers = await getBorrowedByUser(db, itemId);
      const borrower = borrowers.find((b) => b.user_id === resolution.user_id);

      if (!borrower || borrower.borrowed < resolution.quantity) {
        throw new ConflictError(
          `User ${resolution.user_id} does not have ${resolution.quantity} of this item borrowed`
        );
      }

      // Map resolution status to transaction_items status
      const txStatus =
        resolution.status === "returned"
          ? "normal"
          : resolution.status === "lost"
          ? "lost"
          : "damaged";

      // Create a return transaction for this resolution
      const txId = crypto.randomUUID();
      const idempotencyKey = crypto.randomUUID();

      await db.insert(transactions).values({
        id: txId,
        type: "return",
        user_id: resolution.user_id,
        created_at: now,
        idempotency_key: idempotencyKey,
      });

      await db.insert(transaction_items).values({
        id: crypto.randomUUID(),
        transaction_id: txId,
        bucket_id: bucketId,
        item_type_id: itemId,
        quantity: resolution.quantity,
        direction: 1, // return = +1
        status: txStatus,
      });

      resolvedTransactions.push({
        transaction_id: txId,
        user_id: resolution.user_id,
        quantity: resolution.quantity,
        status: resolution.status,
      });
    }

    // If items were lost or damaged, we should decrease the item quantity
    // to reflect that those items are no longer in circulation
    const lostOrDamaged = body.resolutions
      .filter((r) => r.status === "lost" || r.status === "damaged")
      .reduce((sum, r) => sum + r.quantity, 0);

    if (lostOrDamaged > 0) {
      const newQuantity = Math.max(1, item.quantity - lostOrDamaged);
      await db
        .update(item_types)
        .set({ quantity: newQuantity })
        .where(eq(item_types.id, itemId));
    }

    return c.json({
      data: {
        resolved: resolvedTransactions,
        new_borrowed: await getBorrowedCount(db, itemId),
      },
    });
  }
);

// ─── DELETE /buckets/:id — delete bucket (admin only) ───────────────────────

bucketRoutes.delete("/:id", requireRole("admin"), async (c) => {
  const id = c.req.param("id");
  const db = c.get("db");

  const existing = (
    await db.select().from(buckets).where(eq(buckets.id, id)).limit(1)
  )[0];
  if (!existing) throw new NotFoundError("Bucket");

  // Check if any items are currently borrowed — collect full details
  const items = await db
    .select()
    .from(item_types)
    .where(eq(item_types.bucket_id, id));

  const itemsWithBorrowers: Array<{
    item_type_id: string;
    item_name: string;
    item_emoji: string;
    total_borrowed: number;
    borrowers: Array<{
      user_id: string;
      full_name: string;
      scout_id: string;
      borrowed: number;
    }>;
  }> = [];

  for (const item of items) {
    const borrowed = await getBorrowedCount(db, item.id);
    if (borrowed > 0) {
      const borrowers = await getBorrowedByUser(db, item.id);
      itemsWithBorrowers.push({
        item_type_id: item.id,
        item_name: item.name,
        item_emoji: item.emoji,
        total_borrowed: borrowed,
        borrowers: borrowers.filter((b) => b.borrowed > 0),
      });
    }
  }

  if (itemsWithBorrowers.length > 0) {
    // Return 409 with full borrower details so frontend can show resolution sheet
    return c.json(
      {
        error: "bucket_has_borrowed_items",
        message: `Cannot delete bucket — ${itemsWithBorrowers.length} item(s) have borrowed units`,
        bucket_id: id,
        bucket_name: existing.name,
        items_with_borrowers: itemsWithBorrowers,
      },
      409
    );
  }

  // Soft-delete item_types: detach from bucket but keep rows so
  // transaction history still has item names and emojis via LEFT JOIN
  await db
    .update(item_types)
    .set({ bucket_id: "__deleted__" })
    .where(eq(item_types.bucket_id, id));

  // Hard-delete the bucket itself
  await db.delete(buckets).where(eq(buckets.id, id));

  return c.json({ message: "Bucket deleted" });
});

export { bucketRoutes };