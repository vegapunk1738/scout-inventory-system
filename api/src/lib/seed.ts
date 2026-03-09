import { eq } from "drizzle-orm";
import { DrizzleD1Database } from "drizzle-orm/d1";
import { users } from "../db/schema";
import { hashPassword } from "./crypto";

/** Super Admin has a fixed UUID — used to protect against edit/delete. */
export const SEED_USERS = [
  {
    id: "00000000-0000-0000-0000-000000000001",
    scout_id: "0001",
    full_name: "Super Admin",
    password: "",
    role: "admin" as const,
  },
  {
    id: "00000000-0000-0000-0000-000000000002",
    scout_id: "0002",
    full_name: "Rony Mawad",
    password: "",
    role: "scout" as const,
  },
];

/**
 * Ensures seed users exist in the database.
 * Runs on every request but short-circuits after the first successful check
 * using a module-level flag (reset on cold start).
 */
let seeded = false;

export async function ensureSeedUsers(
  db: DrizzleD1Database,
  superAdminPassword: string,
  defaultScoutPassword: string
): Promise<void> {
  if (seeded) return;

  for (const seed of SEED_USERS) {
    try {
      const existing = (
        await db
          .select({ id: users.id })
          .from(users)
          .where(eq(users.scout_id, seed.scout_id))
          .limit(1)
      )[0];

      if (!existing) {
        const pw = seed.scout_id === "0001" ? superAdminPassword : defaultScoutPassword;
        const hash = await hashPassword(pw)

        await db.insert(users).values({
          id: seed.id,
          scout_id: seed.scout_id,
          full_name: seed.full_name,
          password_hash: hash,
          role: seed.role,
          created_at: new Date().toISOString(),
        });
      }
    } catch (err) {
      console.error(`SEED ERROR for ${seed.scout_id}:`, err);
    }
  }

  seeded = true;
}