import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";

export const users = sqliteTable("users", {
  id: text("id").primaryKey(),
  scout_id: text("scout_id").unique().notNull(),
  full_name: text("full_name").notNull(),
  password_hash: text("password_hash").notNull(),
  role: text("role", { enum: ["admin", "scout"] }).notNull().default("scout"),
  created_at: text("created_at").notNull(),
});

export const buckets = sqliteTable("buckets", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  barcode: text("barcode").unique().notNull(),
  created_at: text("created_at").notNull(),
  created_by: text("created_by").notNull(),
});

export const item_types = sqliteTable("item_types", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  emoji: text("emoji").notNull(),
  bucket_id: text("bucket_id").notNull(),
  max_quantity: integer("max_quantity").notNull().default(0),
});

export const transactions = sqliteTable("transactions", {
  id: text("id").primaryKey(),
  type: text("type", { enum: ["checkout", "return"] }).notNull(),
  user_id: text("user_id").notNull(),
  created_at: text("created_at").notNull(),
  idempotency_key: text("idempotency_key").unique().notNull(),
});

export const transaction_items = sqliteTable("transaction_items", {
  id: text("id").primaryKey(),
  transaction_id: text("transaction_id").notNull(),
  bucket_id: text("bucket_id").notNull(),
  item_type_id: text("item_type_id").notNull(),
  quantity: integer("quantity").notNull(),
  direction: integer("direction").notNull(),
});