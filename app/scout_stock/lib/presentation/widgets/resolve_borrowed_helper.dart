import 'package:flutter/material.dart';

import 'package:scout_stock/domain/models/bucket.dart';
import 'package:scout_stock/presentation/widgets/borrowed_resolution_sheet.dart';
import 'package:scout_stock/state/notifiers/buckets_notifier.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Model for user-scoped borrowed items (used by user deletion flow)
// ═════════════════════════════════════════════════════════════════════════════

/// Represents a single item type that a user has currently borrowed.
/// Returned by the "GET /users/:scoutId/borrowed-items" endpoint.
class UserBorrowedItemInfo {
  const UserBorrowedItemInfo({
    required this.bucketId,
    required this.bucketName,
    required this.itemTypeId,
    required this.itemName,
    required this.itemEmoji,
    required this.borrowed,
  });

  final String bucketId;
  final String bucketName;
  final String itemTypeId;
  final String itemName;
  final String itemEmoji;
  final int borrowed;

  factory UserBorrowedItemInfo.fromJson(Map<String, dynamic> json) {
    return UserBorrowedItemInfo(
      bucketId: json['bucket_id'] as String,
      bucketName: json['bucket_name'] as String,
      itemTypeId: json['item_type_id'] as String,
      itemName: json['item_name'] as String,
      itemEmoji: json['item_emoji'] as String,
      borrowed: json['borrowed'] as int,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Bucket deletion — resolve all borrowed items in one sheet
// ═════════════════════════════════════════════════════════════════════════════

/// Resolves all borrowed items for a bucket in a single sheet before deletion.
Future<bool> resolveAllBorrowedItems({
  required BuildContext context,
  required String bucketId,
  required String bucketName,
  required List<BucketItem> items,
  required BucketsNotifier notifier,
}) async {
  final itemsWithBorrowed = items.where((i) => i.borrowed > 0).toList();
  if (itemsWithBorrowed.isEmpty) return true;

  final entries = <BulkResolutionEntry>[];
  for (final item in itemsWithBorrowed) {
    if (!context.mounted) return false;

    final borrowers = await notifier.fetchBorrowers(bucketId, item.id);
    if (borrowers.isEmpty) continue;

    entries.add(BulkResolutionEntry(
      bucketId: bucketId,
      itemId: item.id,
      itemName: item.name,
      itemEmoji: item.emoji,
      borrowers: borrowers,
    ));
  }

  if (entries.isEmpty) return true;
  if (!context.mounted) return false;

  final result = await showBulkBorrowedResolutionSheet(
    context,
    subtitle: bucketName,
    entries: entries,
    bannerText:
        'This bucket has ${entries.fold<int>(0, (s, e) => s + e.borrowers.fold<int>(0, (ss, b) => ss + b.borrowed))} '
        'borrowed item${entries.length != 1 ? 's' : ''} across ${entries.length} '
        'item type${entries.length != 1 ? 's' : ''}. '
        'Resolve all of them to proceed with deletion.',
    buttonLabel: 'Resolve & Delete',
  );

  if (result == null) return false;

  for (final entry in entries) {
    final resolutions = result.resolutionsByItemId[entry.itemId];
    if (resolutions == null || resolutions.isEmpty) continue;

    await notifier.resolveBorrowed(
      bucketId,
      entry.itemId,
      resolutions: resolutions,
    );
  }

  return true;
}

// ═════════════════════════════════════════════════════════════════════════════
// User deletion — resolve all items a user has borrowed (across buckets)
// ═════════════════════════════════════════════════════════════════════════════

/// Resolves all items a specific user has borrowed before their account
/// is deleted. Shows one bulk sheet with every item the user holds.
///
/// [borrowedItems] comes from the "GET /users/:scoutId/borrowed-items"
/// endpoint. The resolution calls go through [bucketsNotifier] since the
/// resolve endpoint is bucket-scoped.
///
/// Returns `true` if all items were resolved, `false` if the user cancelled.
Future<bool> resolveUserBorrowedItems({
  required BuildContext context,
  required String userId,
  required String userName,
  required String userScoutId,
  required List<UserBorrowedItemInfo> borrowedItems,
  required BucketsNotifier bucketsNotifier,
}) async {
  if (borrowedItems.isEmpty) return true;
  if (!context.mounted) return false;

  // Build one entry per item type — each with the single user as borrower.
  final entries = borrowedItems.map((item) {
    return BulkResolutionEntry(
      bucketId: item.bucketId,
      itemId: item.itemTypeId,
      itemName: '${item.itemName}  ·  ${item.bucketName}',
      itemEmoji: item.itemEmoji,
      borrowers: [
        BorrowerInfo(
          userId: userId,
          fullName: userName,
          scoutId: userScoutId,
          borrowed: item.borrowed,
        ),
      ],
    );
  }).toList();

  final totalBorrowed = borrowedItems.fold<int>(0, (s, i) => s + i.borrowed);

  final result = await showBulkBorrowedResolutionSheet(
    context,
    subtitle: userName,
    entries: entries,
    bannerText:
        '$userName has $totalBorrowed borrowed item${totalBorrowed != 1 ? 's' : ''} '
        'across ${borrowedItems.length} item type${borrowedItems.length != 1 ? 's' : ''}. '
        'Resolve all of them to proceed with deletion.',
    buttonLabel: 'Resolve & Delete',
  );

  if (result == null) return false;

  // Submit resolutions per item — each goes to its respective bucket.
  for (final entry in entries) {
    final resolutions = result.resolutionsByItemId[entry.itemId];
    if (resolutions == null || resolutions.isEmpty) continue;

    await bucketsNotifier.resolveBorrowed(
      entry.bucketId!,
      entry.itemId,
      resolutions: resolutions,
    );
  }

  return true;
}

// ═════════════════════════════════════════════════════════════════════════════
// Single item helpers (unchanged)
// ═════════════════════════════════════════════════════════════════════════════

/// Resolves ALL borrowed for a single item (e.g. before removing it entirely).
Future<bool> resolveSingleBorrowedItem({
  required BuildContext context,
  required String bucketId,
  required String itemTypeId,
  required String itemName,
  required String itemEmoji,
  required BucketsNotifier notifier,
}) async {
  if (!context.mounted) return false;

  final borrowers = await notifier.fetchBorrowers(bucketId, itemTypeId);
  if (borrowers.isEmpty) return true;
  if (!context.mounted) return false;

  final result = await showBorrowedResolutionSheet(
    context,
    itemName: itemName,
    itemEmoji: itemEmoji,
    borrowers: borrowers,
  );

  if (result == null) return false;

  await notifier.resolveBorrowed(
    bucketId,
    itemTypeId,
    resolutions: result.resolutions,
  );

  return true;
}

/// Resolves exactly [resolveCount] items for a single item type.
Future<bool> resolvePartialBorrowed({
  required BuildContext context,
  required String bucketId,
  required String itemTypeId,
  required String itemName,
  required String itemEmoji,
  required int resolveCount,
  required BucketsNotifier notifier,
}) async {
  if (!context.mounted) return false;

  final borrowers = await notifier.fetchBorrowers(bucketId, itemTypeId);
  if (borrowers.isEmpty) return true;
  if (!context.mounted) return false;

  final result = await showBorrowedResolutionSheet(
    context,
    itemName: itemName,
    itemEmoji: itemEmoji,
    borrowers: borrowers,
    resolveCount: resolveCount,
  );

  if (result == null) return false;

  await notifier.resolveBorrowed(
    bucketId,
    itemTypeId,
    resolutions: result.resolutions,
  );

  return true;
}