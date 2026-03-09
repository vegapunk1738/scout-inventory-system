import { Context, Next } from "hono";
import { Env, JwtPayload } from "../types";
import { UnauthorizedError, ForbiddenError } from "../lib/errors";

function base64UrlToBuffer(b64url: string): ArrayBuffer {
  const b64 = b64url.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64.padEnd(b64.length + ((4 - (b64.length % 4)) % 4), "=");
  const bin = atob(padded);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer as ArrayBuffer;
}

async function verifyJwt(token: string, secret: string): Promise<JwtPayload> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new UnauthorizedError("Malformed token");

  const [headerB64, payloadB64, signatureB64] = parts;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret).buffer as ArrayBuffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`).buffer as ArrayBuffer;
  const signature = base64UrlToBuffer(signatureB64);
  const valid = await crypto.subtle.verify("HMAC", key, signature, data);
  if (!valid) throw new UnauthorizedError("Invalid token signature");

  const payload = JSON.parse(
    new TextDecoder().decode(base64UrlToBuffer(payloadB64))
  ) as JwtPayload;

  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
    throw new UnauthorizedError("Token expired");
  }

  return payload;
}

export const auth = () => {
  return async (c: Context<Env>, next: Next) => {
    const header = c.req.header("Authorization");
    if (!header?.startsWith("Bearer ")) {
      throw new UnauthorizedError("Missing or invalid Authorization header");
    }

    const payload = await verifyJwt(header.slice(7), c.env.JWT_SECRET);
    c.set("jwtPayload", payload);
    await next();
  };
};

export const requireRole = (...roles: Array<"admin" | "scout">) => {
  return async (c: Context<Env>, next: Next) => {
    const payload = c.get("jwtPayload");
    if (!payload) throw new UnauthorizedError();
    if (!roles.includes(payload.role)) throw new ForbiddenError();
    await next();
  };
};

export const authAllowExpired = () => {
  return async (c: Context<Env>, next: Next) => {
    const header = c.req.header("Authorization");
    if (!header?.startsWith("Bearer ")) {
      throw new UnauthorizedError("Missing or invalid Authorization header");
    }

    const payload = await verifyJwtIgnoreExpiry(header.slice(7), c.env.JWT_SECRET);
    c.set("jwtPayload", payload);
    await next();
  };
};

async function verifyJwtIgnoreExpiry(token: string, secret: string): Promise<JwtPayload> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new UnauthorizedError("Malformed token");

  const [headerB64, payloadB64, signatureB64] = parts;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret).buffer as ArrayBuffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`).buffer as ArrayBuffer;
  const signature = base64UrlToBuffer(signatureB64);
  const valid = await crypto.subtle.verify("HMAC", key, signature, data);
  if (!valid) throw new UnauthorizedError("Invalid token signature");

  return JSON.parse(
    new TextDecoder().decode(base64UrlToBuffer(payloadB64))
  ) as JwtPayload;
}