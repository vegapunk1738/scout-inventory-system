import { Env } from "../types";
import { audit_logs } from "../db/schema";

type AuditEntry = {
  actor_id: string;
  entity: "bucket" | "user" | "item";
  entity_id: string;
  action: "created" | "updated" | "deleted" | "resolved";
  summary: string;
  meta?: Record<string, unknown>;
};

/**
 * Insert an audit log entry. Fire-and-forget — errors are logged but don't
 * break the caller.
 */
export async function writeAuditLog(
  db: Env["Variables"]["db"],
  entry: AuditEntry
): Promise<void> {
  try {
    await db.insert(audit_logs).values({
      id: crypto.randomUUID(),
      actor_id: entry.actor_id,
      entity: entry.entity,
      entity_id: entry.entity_id,
      action: entry.action,
      summary: entry.summary,
      meta: entry.meta ? JSON.stringify(entry.meta) : null,
      created_at: new Date().toISOString(),
    });
  } catch (err) {
    console.error("Failed to write audit log:", err);
  }
}