import { Hono } from "hono";
import { cors } from "hono/cors";
import { drizzle } from "drizzle-orm/d1";
import { Env } from "./types";
import { errorHandler } from "./middleware/error-handler";
import { authRoutes } from "./routes/auth";
import { userRoutes } from "./routes/users";
import { bucketRoutes } from "./routes/buckets";
import { transactionRoutes } from "./routes/transactions";
import { ensureSeedUsers } from "./lib/seed";

const app = new Hono<Env>();

// ─── Global middleware ──────────────────────────────────────────────────────

app.use("/*", cors());

app.use("/*", async (c, next) => {
  const db = drizzle(c.env.DB);
  c.set("db", db);

  // Auto-seed on cold start (no-ops after first successful run)
  await ensureSeedUsers(db, c.env.SUPER_ADMIN_PASSWORD, c.env.DEFAULT_SCOUT_PASSWORD);

  await next();
});

// ─── Routes ─────────────────────────────────────────────────────────────────

app.get("/health", (c) => c.json({ status: "ok" }));

app.route("/auth", authRoutes);
app.route("/users", userRoutes);
app.route("/buckets", bucketRoutes);
app.route("/transactions", transactionRoutes);

// ─── Error handling ─────────────────────────────────────────────────────────

app.onError(errorHandler);

export default app;