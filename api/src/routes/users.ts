import { Hono } from "hono";
import { z } from "zod";
import { eq, sql, isNull, and } from "drizzle-orm";
import { Env } from "../types";
import { buckets, item_types, transaction_items, transactions, users } from "../db/schema";
import { hashPassword } from "../lib/crypto";
import { NotFoundError, ConflictError, ForbiddenError } from "../lib/errors";
import { auth, requireRole } from "../middleware/auth";
import { SEED_USERS } from "../lib/seed";
import { writeAuditLog } from "../lib/audit";

// ─── Validation schemas ─────────────────────────────────────────────────────
const CreateUserBody = z.object({
  scout_id: z
    .string()
    .min(1, "Scout ID is required")
    .max(10)
    .regex(/^\d+$/, "Scout ID must contain only digits"),
  full_name: z.string().min(2, "Name must be at least 2 characters").max(100).trim(),
  password: z.string().min(6, "Password must be at least 6 characters").max(128),
  role: z.enum(["admin", "scout"]).default("scout"),
});

const UpdateUserBody = z
  .object({
    full_name: z.string().min(2, "Name must be at least 2 characters").max(100).trim().optional(),
    password: z.string().min(6, "Password must be at least 6 characters").max(128).optional(),
    role: z.enum(["admin", "scout"]).optional(),
  })
  .refine((d) => Object.keys(d).length > 0, {
    message: "At least one field must be provided",
  });

// ─── Helpers ────────────────────────────────────────────────────────────────

function sanitize<T extends { password_hash: string }>(
  row: T
): Omit<T, "password_hash"> {
  const { password_hash: _, ...safe } = row;
  return safe;
}

function isSuperAdmin(user: { id: string; scout_id: string }): boolean {
  return (
    user.id === SEED_USERS[0].id ||
    user.scout_id === SEED_USERS[0].scout_id
  );
}

/**
 * Finds the next available scout_id by looking at the max numeric value
 * currently in the table and incrementing by 1. Pads to 4 digits minimum.
 */
async function findNextScoutId(db: Env["Variables"]["db"]): Promise<string> {
  const result = await db
    .select({ maxId: sql<string>`MAX(CAST(scout_id AS INTEGER))` })
    .from(users)
    .limit(1);

  const maxNum = parseInt(result[0]?.maxId ?? "0", 10) || 0;
  const next = maxNum + 1;
  return next.toString().padStart(4, "0");
}

/**
 * Finds an active (non-deleted) user by scout_id or UUID.
 * Returns null if not found or soft-deleted.
 */
async function findActiveUser(
  db: Env["Variables"]["db"],
  identifier: string
) {
  const isScoutId = /^\d+$/.test(identifier);
  const condition = isScoutId
    ? and(eq(users.scout_id, identifier), isNull(users.deleted_at))
    : and(eq(users.id, identifier), isNull(users.deleted_at));

  const row = (
    await db.select().from(users).where(condition).limit(1)
  )[0];

  return row ?? null;
}

// ─── Routes ─────────────────────────────────────────────────────────────────

const userRoutes = new Hono<Env>();

userRoutes.use("/*", auth(), requireRole("admin"));

// GET /users/next-scout-id — returns the next available scout_id
userRoutes.get("/next-scout-id", async (c) => {
  const db = c.get("db");
  const scoutId = await findNextScoutId(db);
  return c.json({ scout_id: scoutId });
});

// GET /users — list all active (non-deleted) users
userRoutes.get("/", async (c) => {
  const db = c.get("db");
  const rows = await db
    .select()
    .from(users)
    .where(isNull(users.deleted_at));
  return c.json({ data: rows.map(sanitize) });
});

// GET /users/by-scout-id/:scoutId/borrowed-items — all items a user currently has borrowed
userRoutes.get("/by-scout-id/:scoutId/borrowed-items", async (c) => {
  const scoutId = c.req.param("scoutId");
  const db = c.get("db");

  const user = (
    await db
      .select()
      .from(users)
      .where(eq(users.scout_id, scoutId))
      .limit(1)
  )[0];
  if (!user) throw new NotFoundError("User");

  // Find all item types this user has net-positive borrows for
  const rows = await db
    .select({
      item_type_id: transaction_items.item_type_id,
      bucket_id: transaction_items.bucket_id,
      borrowed: sql<number>`
        SUM(CASE WHEN ${transaction_items.direction} = -1 THEN ${transaction_items.quantity} ELSE 0 END)
        - SUM(CASE WHEN ${transaction_items.direction} = 1 THEN ${transaction_items.quantity} ELSE 0 END)
      `,
    })
    .from(transaction_items)
    .innerJoin(transactions, eq(transaction_items.transaction_id, transactions.id))
    .where(eq(transactions.user_id, user.id))
    .groupBy(transaction_items.item_type_id, transaction_items.bucket_id)
    .having(sql`
      SUM(CASE WHEN ${transaction_items.direction} = -1 THEN ${transaction_items.quantity} ELSE 0 END)
      - SUM(CASE WHEN ${transaction_items.direction} = 1 THEN ${transaction_items.quantity} ELSE 0 END)
      > 0
    `);

  // Hydrate with item + bucket names
  const result = await Promise.all(
    rows.map(async (row) => {
      const item = (
        await db
          .select()
          .from(item_types)
          .where(eq(item_types.id, row.item_type_id))
          .limit(1)
      )[0];
      const bucket = (
        await db
          .select()
          .from(buckets)
          .where(eq(buckets.id, row.bucket_id))
          .limit(1)
      )[0];
      return {
        bucket_id: row.bucket_id,
        bucket_name: bucket?.name ?? "Unknown",
        item_type_id: row.item_type_id,
        item_name: item?.name ?? "Unknown",
        item_emoji: item?.emoji ?? "📦",
        borrowed: Number(row.borrowed),
      };
    })
  );

  return c.json({ data: result });
});

// GET /users/:identifier — single active user by scout_id or UUID
userRoutes.get("/:identifier", async (c) => {
  const identifier = c.req.param("identifier");
  const db = c.get("db");

  const row = await findActiveUser(db, identifier);
  if (!row) throw new NotFoundError("User");

  return c.json({ data: sanitize(row) });
});

// POST /users — creates a user; auto-increments scout_id on conflict
userRoutes.post("/", async (c) => {
  const body = CreateUserBody.parse(await c.req.json());
  const db = c.get("db");

  // Check name uniqueness among active users.
  const byName = (
    await db
      .select({ id: users.id })
      .from(users)
      .where(and(eq(users.full_name, body.full_name), isNull(users.deleted_at)))
      .limit(1)
  )[0];
  if (byName) {
    throw new ConflictError(`Name "${body.full_name}" is already taken`);
  }

  // Try the requested scout_id first, then auto-increment on conflict.
  let scoutId = body.scout_id;
  const maxAttempts = 10;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const exists = (
      await db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.scout_id, scoutId))
        .limit(1)
    )[0];

    if (!exists) break; // scout_id is available

    if (attempt === maxAttempts - 1) {
      throw new ConflictError("Could not assign a unique Scout ID. Please try again.");
    }

    // Auto-increment: find next available
    scoutId = await findNextScoutId(db);
  }

  const row = (
    await db
      .insert(users)
      .values({
        id: crypto.randomUUID(),
        scout_id: scoutId,
        full_name: body.full_name,
        password_hash: await hashPassword(body.password),
        role: body.role,
        created_at: new Date().toISOString(),
      })
      .returning()
  )[0];

  await writeAuditLog(db, {
    actor_id: c.get("jwtPayload").sub,
    entity: "user",
    entity_id: row.id,
    action: "created",
    summary: `Created user "${body.full_name}" (Scout #${scoutId})`,
    meta: { scout_id: scoutId, role: body.role },
  });

  return c.json({ data: sanitize(row) }, 201);
});

// PATCH /users/:identifier — update an active user
userRoutes.patch("/:identifier", async (c) => {
  const identifier = c.req.param("identifier");
  const body = UpdateUserBody.parse(await c.req.json());
  const db = c.get("db");

  const existing = await findActiveUser(db, identifier);
  if (!existing) throw new NotFoundError("User");

  if (isSuperAdmin(existing)) {
    throw new ForbiddenError("Super Admin cannot be modified");
  }

  if (body.full_name && body.full_name !== existing.full_name) {
    const conflict = (
      await db
        .select({ id: users.id })
        .from(users)
        .where(and(eq(users.full_name, body.full_name), isNull(users.deleted_at)))
        .limit(1)
    )[0];
    if (conflict) {
      throw new ConflictError(`Name "${body.full_name}" is already taken`);
    }
  }

  const updates: Record<string, unknown> = {};
  if (body.full_name) updates.full_name = body.full_name;
  if (body.role) updates.role = body.role;
  if (body.password) updates.password_hash = await hashPassword(body.password);

  const updated = (
    await db
      .update(users)
      .set(updates)
      .where(eq(users.id, existing.id))
      .returning()
  )[0];

  await writeAuditLog(db, {
    actor_id: c.get("jwtPayload").sub,
    entity: "user",
    entity_id: existing.id,
    action: "updated",
    summary: `Updated user "${updated.full_name}" (Scout #${existing.scout_id})`,
    meta: {
      fields_changed: Object.keys(body).filter((k) => k !== "password"),
    },
  });

  return c.json({ data: sanitize(updated) });
});

// DELETE /users/:identifier — soft-delete user
userRoutes.delete("/:identifier", async (c) => {
  const identifier = c.req.param("identifier");
  const db = c.get("db");

  const existing = await findActiveUser(db, identifier);
  if (!existing) throw new NotFoundError("User");

  if (isSuperAdmin(existing)) {
    throw new ForbiddenError("Super Admin cannot be deleted");
  }

  // Soft-delete: set deleted_at timestamp.
  // The row stays so transaction history JOINs still resolve
  // the user's name and scout_id.
  const now = new Date().toISOString();
  await db
    .update(users)
    .set({ deleted_at: now })
    .where(eq(users.id, existing.id));

  await writeAuditLog(db, {
    actor_id: c.get("jwtPayload").sub,
    entity: "user",
    entity_id: existing.id,
    action: "deleted",
    summary: `Deleted user "${existing.full_name}" (Scout #${existing.scout_id})`,
  });

  return c.json({ message: "User deleted" });
});

export { userRoutes };