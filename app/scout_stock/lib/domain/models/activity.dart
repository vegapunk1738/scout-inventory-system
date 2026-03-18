// ─── Activity domain model ──────────────────────────────────────────────────
//
// Represents a single entry in the unified activity feed (transactions + audit
// logs). Parsed from the GET /activity API response.

class ActivityLineItem {
  const ActivityLineItem({
    required this.itemName,
    required this.itemEmoji,
    required this.bucketName,
    required this.bucketBarcode,
    required this.quantity,
    required this.status,
  });

  final String itemName;
  final String itemEmoji;
  final String bucketName;
  final String bucketBarcode;
  final int quantity;
  final String status; // 'normal', 'lost', 'damaged'

  factory ActivityLineItem.fromJson(Map<String, dynamic> json) {
    return ActivityLineItem(
      itemName: json['item_name'] as String? ?? 'Unknown item',
      itemEmoji: json['item_emoji'] as String? ?? '📦',
      bucketName: json['bucket_name'] as String? ?? 'Unknown bucket',
      bucketBarcode: json['bucket_barcode'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
      status: json['status'] as String? ?? 'normal',
    );
  }
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.kind,
    required this.actorId,
    required this.actorName,
    required this.actorScoutId,
    required this.entity,
    required this.summary,
    required this.targetUserName,
    required this.targetUserScoutId,
    required this.meta,
    required this.createdAt,
    required this.lineItems,
  });

  final String id;

  /// e.g. 'checkout', 'return', 'resolved_lost', 'resolved_damaged',
  ///      'bucket_created', 'bucket_updated', 'bucket_deleted',
  ///      'user_created', 'user_updated', 'user_deleted'
  final String kind;

  final String actorId;
  final String actorName;

  /// Scout ID of the actor (e.g. "0042"). Populated for transactions.
  final String actorScoutId;

  /// 'item', 'bucket', or 'user'
  final String entity;

  /// Full human-readable summary from the backend.
  final String summary;

  /// Name of the target user whose items were affected.
  /// Only non-empty when an admin acted on behalf of a scout.
  final String targetUserName;

  /// Scout ID of the target user.
  final String targetUserScoutId;

  /// Raw meta (parsed JSON). For transactions this is a list of line items.
  /// For audit logs this may contain details about the affected entity.
  final dynamic meta;

  final DateTime createdAt;

  /// Parsed line items (only populated for transaction entries).
  final List<ActivityLineItem> lineItems;

  // ── Convenience getters ─────────────────────────────────────────────────

  bool get isTransaction => entity == 'item';
  bool get isCheckout => kind == 'checkout';
  bool get isReturn => kind == 'return';
  bool get isResolvedLost => kind == 'resolved_lost';
  bool get isResolvedDamaged => kind == 'resolved_damaged';
  bool get isResolved => isResolvedLost || isResolvedDamaged;
  bool get isBucketEvent => entity == 'bucket';
  bool get isUserEvent => entity == 'user';

  /// Short action label (used as fallback).
  /// e.g. "checked out", "returned", "resolved (lost)"
  String get actionLabel {
    switch (kind) {
      case 'checkout':
        return 'checked out';
      case 'return':
        return 'returned';
      case 'resolved_lost':
        return 'resolved (lost)';
      case 'resolved_damaged':
        return 'resolved (damaged)';
      case 'bucket_created':
        return 'created bucket';
      case 'bucket_updated':
        return 'updated bucket';
      case 'bucket_deleted':
        return 'deleted bucket';
      case 'user_created':
        return 'created user';
      case 'user_updated':
        return 'updated user';
      case 'user_deleted':
        return 'deleted user';
      default:
        return kind;
    }
  }

  /// Rich detail label for the card subtitle. Shows item counts for
  /// transactions and target entity info for audit events.
  ///
  /// Examples:
  ///   "checked out 3 items"
  ///   "returned 2 items"
  ///   "resolved 1 item (lost)"
  ///   "created user Jean Dupont (#0042)"
  ///   "deleted bucket Tent Pegs"
  String get detailLabel {
    if (isTransaction) {
      return _transactionDetailLabel;
    }
    return _auditDetailLabel;
  }

  String get _transactionDetailLabel {
    // Compute total quantity from line items
    final totalQty = lineItems.fold<int>(0, (sum, li) => sum + li.quantity);
    final itemWord = totalQty == 1 ? 'item' : 'items';

    // "for X (#ID)" suffix — only when an admin acted on behalf of a scout
    final forSuffix = targetUserName.isNotEmpty
        ? targetUserScoutId.isNotEmpty
            ? '\nfor $targetUserName (#$targetUserScoutId)'
            : '\nfor $targetUserName'
        : '';

    switch (kind) {
      case 'checkout':
        return 'checked out $totalQty $itemWord$forSuffix';
      case 'return':
        return 'returned $totalQty $itemWord$forSuffix';
      case 'resolved_lost':
        return 'resolved $totalQty $itemWord (lost)$forSuffix';
      case 'resolved_damaged':
        return 'resolved $totalQty $itemWord (damaged)$forSuffix';
      default:
        return '$totalQty $itemWord$forSuffix';
    }
  }

  String get _auditDetailLabel {
    final metaMap = (meta is Map<String, dynamic>) ? meta as Map<String, dynamic> : null;

    if (isBucketEvent && metaMap != null) {
      return _bucketDetailLabel(metaMap);
    }

    if (isUserEvent && metaMap != null) {
      return _userDetailLabel(metaMap);
    }

    // Fallback: strip actor name from summary if present
    final stripped = summary.startsWith(actorName)
        ? summary.substring(actorName.length).trimLeft()
        : summary;
    if (stripped.isNotEmpty) return stripped;

    return actionLabel;
  }

  String _bucketDetailLabel(Map<String, dynamic> m) {
    final name = m['name'] as String?;
    final barcode = m['barcode'] as String?;
    final header = name != null
        ? '${_auditActionWord} bucket $name${barcode != null ? ' ($barcode)' : ''}'
        : '${_auditActionWord} bucket';

    // Created: show item count + item names
    if (kind == 'bucket_created') {
      final items = m['items'] as List?;
      if (items != null && items.isNotEmpty) {
        final itemSummary = items
            .take(3)
            .map((i) {
              final n = (i as Map)['name'] ?? '?';
              final q = (i)['quantity'] ?? 0;
              return '$n ×$q';
            })
            .join(', ');
        final overflow = items.length > 3 ? ' +${items.length - 3} more' : '';
        return '$header\n${items.length} items: $itemSummary$overflow';
      }
      final count = m['item_count'] as int?;
      if (count != null) return '$header\n$count items';
      return header;
    }

    // Updated: show what changed
    if (kind == 'bucket_updated') {
      final changes = (m['changes'] as List?)?.cast<String>() ?? [];
      if (changes.isNotEmpty) {
        return '$header\n${changes.join(', ')}';
      }
      return header;
    }

    // Deleted: show item count
    if (kind == 'bucket_deleted') {
      final count = m['item_count'] as int?;
      if (count != null) return '$header\n$count items removed';
      return header;
    }

    return header;
  }

  String _userDetailLabel(Map<String, dynamic> m) {
    final name = m['full_name'] as String?;
    final scoutId = m['scout_id'] as String?;
    final role = m['role'] as String?;
    final header = name != null
        ? '${_auditActionWord} user $name${scoutId != null ? ' (#$scoutId)' : ''}'
        : '${_auditActionWord} user';

    // Created: show role
    if (kind == 'user_created') {
      if (role != null) return '$header\nrole: $role';
      return header;
    }

    // Updated: show what changed
    if (kind == 'user_updated') {
      final changes = (m['changes'] as List?)?.cast<String>() ?? [];
      if (changes.isNotEmpty) {
        return '$header\n${changes.join(', ')}';
      }
      return header;
    }

    // Deleted: show role
    if (kind == 'user_deleted') {
      if (role != null) return '$header\nrole: $role';
      return header;
    }

    return header;
  }

  String get _auditActionWord {
    if (kind.endsWith('_created')) return 'created';
    if (kind.endsWith('_updated')) return 'updated';
    if (kind.endsWith('_deleted')) return 'deleted';
    return '';
  }

  // ── Factory ─────────────────────────────────────────────────────────────

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['meta'];

    // Parse line items from meta if it's a JSON array
    List<ActivityLineItem> lineItems = [];
    if (rawMeta is List) {
      lineItems = rawMeta
          .whereType<Map<String, dynamic>>()
          .map(ActivityLineItem.fromJson)
          .toList();
    }

    return ActivityEntry(
      id: json['id'] as String,
      kind: json['kind'] as String,
      actorId: json['actor_id'] as String? ?? '',
      actorName: json['actor_name'] as String? ?? 'Unknown',
      actorScoutId: json['actor_scout_id'] as String? ?? '',
      entity: json['entity'] as String? ?? 'item',
      summary: json['summary'] as String? ?? '',
      targetUserName: json['target_user_name'] as String? ?? '',
      targetUserScoutId: json['target_user_scout_id'] as String? ?? '',
      meta: rawMeta,
      createdAt: DateTime.parse(json['created_at'] as String),
      lineItems: lineItems,
    );
  }
}