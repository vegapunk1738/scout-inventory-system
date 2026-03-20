import { Env } from "../types";
import { audit_logs } from "../db/schema";

// ─── Types matching the schema enum values ──────────────────────────────────

export type AuditEntity = "bucket" | "user" | "item";
export type AuditAction = "created" | "updated" | "deleted" | "resolved";

// ─── Meta Shapes ────────────────────────────────────────────────────────────

/** Meta for bucket_created */
export interface BucketCreatedMeta {
  bucket_name: string;
  bucket_barcode: string;
  items: Array<{ name: string; emoji: string; quantity: number }>;
}

/** Meta for bucket_updated — carries the diff */
export interface BucketUpdatedMeta {
  bucket_name: string;
  bucket_barcode: string;
  changes: BucketChangeDetail[];
}

export interface BucketChangeDetail {
  kind: "renamed" | "item_added" | "item_removed" | "item_increased" | "item_decreased";
  description: string;
}

/** Meta for bucket_deleted */
export interface BucketDeletedMeta {
  bucket_name: string;
  bucket_barcode: string;
  item_count: number;
}

/** Meta for user_created */
export interface UserCreatedMeta {
  user_name: string;
  scout_id: string;
  role: string;
}

/** Meta for user_updated — carries the diff */
export interface UserUpdatedMeta {
  user_name: string;
  scout_id: string;
  changes: UserChangeDetail[];
}

export interface UserChangeDetail {
  kind: "name_changed" | "role_changed" | "password_reset";
  description: string;
}

/** Meta for user_deleted */
export interface UserDeletedMeta {
  user_name: string;
  scout_id: string;
  role: string;
}

// ─── Write Audit Log ────────────────────────────────────────────────────────

/**
 * Writes an audit log entry matching the audit_logs table schema.
 * Fire-and-forget — errors are logged but never block the main request.
 */
export async function writeAuditLog(
  db: Env["Variables"]["db"],
  params: {
    actor_id: string;
    entity: AuditEntity;
    entity_id: string;
    action: AuditAction;
    summary: string;
    meta?: Record<string, unknown>;
  }
): Promise<void> {
  try {
    await db.insert(audit_logs).values({
      id: crypto.randomUUID(),
      actor_id: params.actor_id,
      entity: params.entity,
      entity_id: params.entity_id,
      action: params.action,
      summary: params.summary,
      meta: params.meta ? JSON.stringify(params.meta) : null,
      created_at: new Date().toISOString(),
    });
  } catch (err) {
    console.error("AUDIT LOG ERROR:", err);
  }
}

// ─── Diff Helpers for Bucket Updates ────────────────────────────────────────

interface OldItem {
  id: string;
  name: string;
  emoji: string;
  quantity: number;
}

interface NewItem {
  id?: string;
  name: string;
  emoji: string;
  quantity: number;
}

/**
 * Computes a list of human-readable change descriptions for a bucket update.
 */
export function computeBucketChanges(
  oldName: string,
  newName: string | undefined,
  oldItems: OldItem[],
  newItems: NewItem[] | undefined
): BucketChangeDetail[] {
  const changes: BucketChangeDetail[] = [];

  // Name change
  if (newName && newName !== oldName) {
    changes.push({
      kind: "renamed",
      description: `updated ${oldName} to ${newName}`,
    });
  }

  if (!newItems) return changes;

  const oldMap = new Map(oldItems.map((i) => [i.id, i]));
  const newIds = new Set(newItems.filter((i) => i.id).map((i) => i.id!));

  // Removed items: in old but not in new
  for (const old of oldItems) {
    if (!newIds.has(old.id)) {
      changes.push({
        kind: "item_removed",
        description: `removed ${old.quantity}× ${old.name}`,
      });
    }
  }

  for (const item of newItems) {
    if (item.id && oldMap.has(item.id)) {
      const old = oldMap.get(item.id)!;

      if (item.quantity > old.quantity) {
        changes.push({
          kind: "item_increased",
          description: `increased ${old.name} from ${old.quantity}× to ${item.quantity}×`,
        });
      } else if (item.quantity < old.quantity) {
        changes.push({
          kind: "item_decreased",
          description: `decreased ${old.name} from ${old.quantity}× to ${item.quantity}×`,
        });
      }

      if (item.name !== old.name) {
        changes.push({
          kind: "renamed",
          description: `updated ${old.name} to ${item.name}`,
        });
      }
    } else {
      // New item
      changes.push({
        kind: "item_added",
        description: `added ${item.quantity}× ${item.name}`,
      });
    }
  }

  return changes;
}

// ─── Diff Helpers for User Updates ──────────────────────────────────────────

export function computeUserChanges(
  existing: { full_name: string; role: string },
  updates: { full_name?: string; role?: string; password?: string }
): UserChangeDetail[] {
  const changes: UserChangeDetail[] = [];

  if (updates.full_name && updates.full_name !== existing.full_name) {
    changes.push({
      kind: "name_changed",
      description: `updated ${existing.full_name} to ${updates.full_name}`,
    });
  }

  if (updates.role && updates.role !== existing.role) {
    const oldRole = existing.role.charAt(0).toUpperCase() + existing.role.slice(1);
    const newRole = updates.role.charAt(0).toUpperCase() + updates.role.slice(1);
    changes.push({
      kind: "role_changed",
      description: `changed role from ${oldRole} to ${newRole}`,
    });
  }

  if (updates.password) {
    changes.push({
      kind: "password_reset",
      description: `password was reset`,
    });
  }

  return changes;
}