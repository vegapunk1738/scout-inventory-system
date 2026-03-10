import { Hono } from "hono";
import { z } from "zod";
import { eq } from "drizzle-orm";
import { Env, JwtPayload } from "../types";
import { users } from "../db/schema";
import { verifyPassword } from "../lib/crypto";
import { UnauthorizedError } from "../lib/errors";
import { auth, authAllowExpired } from "../middleware/auth";

// ─── Validation ─────────────────────────────────────────────────────────────

const LoginBody = z.object({
  identifier: z.string().min(1, "Identifier is required"),
  password: z.string().min(1, "Password is required"),
});

// ─── JWT signing ────────────────────────────────────────────────────────────

function bufferToBase64Url(buffer: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function jsonToBase64Url(obj: unknown): string {
  return bufferToBase64Url(
    new TextEncoder().encode(JSON.stringify(obj)).buffer as ArrayBuffer
  );
}

async function signJwt(
  payload: Omit<JwtPayload, "iat" | "exp">,
  secret: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = jsonToBase64Url({ alg: "HS256", typ: "JWT" });
  const body = jsonToBase64Url({
    ...payload,
    iat: now,
    exp: now + 7 * 24 * 60 * 60, // 7 days
  });

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret).buffer as ArrayBuffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${header}.${body}`).buffer as ArrayBuffer
  );

  return `${header}.${body}.${bufferToBase64Url(signature)}`;
}

// ─── Routes ─────────────────────────────────────────────────────────────────

const authRoutes = new Hono<Env>();

// POST /auth/login — open to everyone
authRoutes.post("/login", async (c) => {
  const { identifier, password } = LoginBody.parse(await c.req.json());
  const db = c.get("db");

  const isScoutId = /^\d+$/.test(identifier);

  const user = (
    await db
      .select()
      .from(users)
      .where(
        isScoutId
          ? eq(users.scout_id, identifier)
          : eq(users.full_name, identifier)
      )
      .limit(1)
  )[0];

  if (!user) throw new UnauthorizedError("Invalid credentials");

  const valid = await verifyPassword(password, user.password_hash);
  if (!valid) throw new UnauthorizedError("Invalid credentials");

  const token = await signJwt(
    {
      sub: user.id,
      scout_id: user.scout_id,
      full_name: user.full_name,
      role: user.role as "admin" | "scout",
    },
    c.env.JWT_SECRET
  );

  return c.json({
    token,
    user: {
      id: user.id,
      scout_id: user.scout_id,
      full_name: user.full_name,
      role: user.role,
    },
  });
});

// POST /auth/refresh — requires valid token, returns a fresh one
authRoutes.post("/refresh", authAllowExpired(), async (c) => {
  const payload = c.get("jwtPayload");
  const db = c.get("db");

  // Re-fetch from DB to pick up any role/name chang es
  const user = (
    await db
      .select()
      .from(users)
      .where(eq(users.id, payload.sub))
      .limit(1)
  )[0];

  if (!user) throw new UnauthorizedError("User no longer exists");

  const token = await signJwt(
    {
      sub: user.id,
      scout_id: user.scout_id,
      full_name: user.full_name,
      role: user.role as "admin" | "scout",
    },
    c.env.JWT_SECRET
  );

  return c.json({
    token,
    user: {
      id: user.id,
      scout_id: user.scout_id,
      full_name: user.full_name,
      role: user.role,
    },
  });
});

export { authRoutes };