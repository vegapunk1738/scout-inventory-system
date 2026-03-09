import { Context } from "hono";
import { ZodError } from "zod";
import { AppError } from "../lib/errors";
import { Env } from "../types";

export function errorHandler(err: Error, c: Context<Env>) {
  if (err instanceof ZodError) {
    return c.json(
      {
        error: "Validation failed",
        details: err.issues.map((e) => ({
          field: e.path.join("."),
          message: e.message,
        })),
      },
      400
    );
  }

  if (err instanceof AppError) {
    return c.json({ error: err.message }, err.statusCode as any);
  }

  console.error("Unhandled error:", err);
  return c.json({ error: "Internal server error" }, 500);
}