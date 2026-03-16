import 'package:flutter/material.dart';

import 'package:scout_stock/domain/models/bucket.dart';
import 'package:scout_stock/presentation/widgets/borrowed_resolution_sheet.dart';
import 'package:scout_stock/state/notifiers/buckets_notifier.dart';

/// Resolves all borrowed items for a bucket before deletion.
///
/// Shows the resolution bottom sheet for each item that has outstanding borrows.
/// Returns `true` if all items were resolved, `false` if the user cancelled.
Future<bool> resolveAllBorrowedItems({
  required BuildContext context,
  required String bucketId,
  required List<BucketItem> items,
  required BucketsNotifier notifier,
}) async {
  final itemsWithBorrowed = items.where((i) => i.borrowed > 0).toList();
  if (itemsWithBorrowed.isEmpty) return true;

  for (final item in itemsWithBorrowed) {
    if (!context.mounted) return false;

    final borrowers = await notifier.fetchBorrowers(bucketId, item.id);
    if (borrowers.isEmpty) continue;
    if (!context.mounted) return false;

    // Resolve ALL borrowed for deletion
    final result = await showBorrowedResolutionSheet(
      context,
      itemName: item.name,
      itemEmoji: item.emoji,
      borrowers: borrowers,
      // resolveCount: null → defaults to total borrowed (resolve all)
    );

    if (result == null) return false;
    await notifier.resolveBorrowed(
      bucketId,
      item.id,
      resolutions: result.resolutions,
    );
  }

  return true;
}

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
    // resolveCount: null → resolve all
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
/// Used when admin decreases quantity below borrowed count — only the
/// excess needs resolving, not all borrowed.
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