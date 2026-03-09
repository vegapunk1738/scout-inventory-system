import { Hono } from "hono";
import { z } from "zod";
import { eq } from "drizzle-orm";
import { Env } from "../types";
import { users } from "../db/schema";
import { hashPassword } from "../lib/crypto";
import { NotFoundError, ConflictError, ForbiddenError } from "../lib/errors";
import { auth, requireRole } from "../middleware/auth";
import { SEED_USERS } from "../lib/seed";

// ─── Validation schemas ─────────────────────────────────────────────────────
const CreateUserBody = z.object({
  scout_id: z
    .string()
    .min(1, "Scout ID is required")
    .max(10)
    .regex(/^\d+$/, "Scout ID must contain only digits"),
  full_name: z.string().min(2).max(100).trim(),
  password: z.string().min(6).max(128),
  role: z.enum(["admin", "scout"]).default("scout"),
});

const UpdateUserBody = z
  .object({
    full_name: z.string().min(2).max(100).trim().optional(),
    password: z.string().min(6).max(128).optional(),
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
  return user.id === SEED_USERS[0].id || user.scout_id === SEED_USERS[0].scout_id;
}

// ─── Routes ─────────────────────────────────────────────────────────────────

const userRoutes = new Hono<Env>();

userRoutes.use("/*", auth(), requireRole("admin"));

// GET /users
userRoutes.get("/", async (c) => {
  const db = c.get("db");
  const rows = await db.select().from(users).all();
  return c.json({ data: rows.map(sanitize) });
});

// GET /users/:identifier
userRoutes.get("/:identifier", async (c) => {
  const identifier = c.req.param("identifier");
  const db = c.get("db");

  const isScoutId = /^\d+$/.test(identifier);

  const row = (
    await db
      .select()
      .from(users)
      .where(
        isScoutId
          ? eq(users.scout_id, identifier)
          : eq(users.id, identifier)
      )
      .limit(1)
  )[0];
  if (!row) throw new NotFoundError("User");

  return c.json({ data: sanitize(row) });
});

// POST /users
userRoutes.post("/", async (c) => {
  const body = CreateUserBody.parse(await c.req.json());
  const db = c.get("db");

  const byScoutId = (
    await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.scout_id, body.scout_id))
      .limit(1)
  )[0];
  if (byScoutId) {
    throw new ConflictError(`Scout ID "${body.scout_id}" is already taken`);
  }

  const byName = (
    await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.full_name, body.full_name))
      .limit(1)
  )[0];
  if (byName) {
    throw new ConflictError(`Name "${body.full_name}" is already taken`);
  }

  const row = (
    await db
      .insert(users)
      .values({
        id: crypto.randomUUID(),
        scout_id: body.scout_id,
        full_name: body.full_name,
        password_hash: await hashPassword(body.password),
        role: body.role,
        created_at: new Date().toISOString(),
      })
      .returning()
  )[0];

  return c.json({ data: sanitize(row) }, 201);
});

// PATCH /users/:identifier
userRoutes.patch("/:identifier", async (c) => {
  const identifier = c.req.param("identifier");
  const body = UpdateUserBody.parse(await c.req.json());
  const db = c.get("db");

  const isScoutId = /^\d+$/.test(identifier);
  const condition = isScoutId
    ? eq(users.scout_id, identifier)
    : eq(users.id, identifier);

  const existing = (
    await db.select().from(users).where(condition).limit(1)
  )[0];
  if (!existing) throw new NotFoundError("User");

  // Protect Super Admin
  if (isSuperAdmin(existing)) {
    throw new ForbiddenError("Super Admin cannot be modified");
  }

  if (body.full_name && body.full_name !== existing.full_name) {
    const conflict = (
      await db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.full_name, body.full_name))
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
    await db.update(users).set(updates).where(eq(users.id, existing.id)).returning()
  )[0];

  return c.json({ data: sanitize(updated) });
});

// DELETE /users/:identifier
userRoutes.delete("/:identifier", async (c) => {
  const identifier = c.req.param("identifier");
  const db = c.get("db");

  const isScoutId = /^\d+$/.test(identifier);
  const condition = isScoutId
    ? eq(users.scout_id, identifier)
    : eq(users.id, identifier);

  // Look up first to check Super Admin protection
  const existing = (
    await db.select().from(users).where(condition).limit(1)
  )[0];
  if (!existing) throw new NotFoundError("User");

  if (isSuperAdmin(existing)) {
    throw new ForbiddenError("Super Admin cannot be deleted");
  }

  await db.delete(users).where(eq(users.id, existing.id));

  return c.json({ message: "User deleted" });
});

export { userRoutes };