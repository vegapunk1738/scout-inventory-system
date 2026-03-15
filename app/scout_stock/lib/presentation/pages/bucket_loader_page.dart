import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/bucket.dart';
import 'package:scout_stock/presentation/pages/bucket_mixed_items_page.dart';
import 'package:scout_stock/presentation/pages/bucket_single_item_page.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/state/providers/buckets_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

/// Fetches a bucket by barcode, then renders [BucketItemPage] (single item)
/// or [BucketMixedItemsPage] (multiple items). Shows loading/error states.
class BucketLoaderPage extends ConsumerStatefulWidget {
  const BucketLoaderPage({super.key, required this.barcode});

  final String barcode;

  @override
  ConsumerState<BucketLoaderPage> createState() => _BucketLoaderPageState();
}

class _BucketLoaderPageState extends ConsumerState<BucketLoaderPage> {
  late Future<Bucket> _fetch;

  @override
  void initState() {
    super.initState();
    _fetch = _fetchBucket();
  }

  Future<Bucket> _fetchBucket() {
    return ref.read(bucketsProvider.notifier).fetchByBarcode(widget.barcode);
  }

  void _retry() {
    setState(() {
      _fetch = _fetchBucket();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);

    return FutureBuilder<Bucket>(
      future: _fetch,
      builder: (context, snap) {
        // ── Loading ─────────────────────────────────────────────────
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(leading: const BackButton()),
            body: Stack(
              children: [
                const Positioned.fill(child: DottedBackground()),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading bucket…',
                        style: t.titleMedium?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.barcode,
                        style: t.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // ── Error ───────────────────────────────────────────────────
        if (snap.hasError) {
          final err = snap.error;
          final isNotFound = err is ApiException && err.isNotFound;

          final emoji = isNotFound ? '🔎' : '⚠️';
          final title = isNotFound
              ? 'Bucket not found'
              : 'Failed to load bucket';
          final subtitle = isNotFound
              ? 'No bucket matches barcode\n${widget.barcode}'
              : err is ApiException
              ? err.message
              : 'Something went wrong. Please try again.';

          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(leading: const BackButton()),
            body: Stack(
              children: [
                const Positioned.fill(child: DottedBackground()),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emoji, style: emojiBase.copyWith(fontSize: 54)),
                        const SizedBox(height: 14),
                        Text(
                          title,
                          style: t.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: t.bodyLarge?.copyWith(color: AppColors.muted),
                          textAlign: TextAlign.center,
                        ),
                        if (!isNotFound) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusXl,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // ── Success ─────────────────────────────────────────────────
        final bucket = snap.data!;

        if (bucket.items.isEmpty) {
          // Bucket exists but has no items — show empty state.
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(leading: const BackButton()),
            body: Stack(
              children: [
                const Positioned.fill(child: DottedBackground()),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🪣', style: emojiBase.copyWith(fontSize: 54)),
                        const SizedBox(height: 14),
                        Text(
                          bucket.name,
                          style: t.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '#${bucket.barcode}',
                          style: t.bodyMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'This bucket has no items yet.\nAsk an admin to add items first.',
                          style: t.bodyLarge?.copyWith(color: AppColors.muted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Single item → BucketItemPage
        if (bucket.items.length == 1) {
          final item = bucket.items.first;
          return BucketItemPage(
            barcode: bucket.barcode,
            bucketId: bucket.id,
            bucketName: bucket.name,
            itemId: item.id,
            itemName: item.name,
            itemEmoji: item.emoji,
            available: item.available,
          );
        }

        // Multiple items → BucketMixedItemsPage
        return BucketMixedItemsPage(
          bucketId: bucket.id,
          bucketBarcode: bucket.barcode,
          bucketName: bucket.name,
          items: bucket.items
              .map(
                (i) => BucketCatalogItem(
                  id: i.id,
                  name: i.name,
                  emoji: i.emoji,
                  available: i.available,
                ),
              )
              .toList(),
        );
      },
    );
  }
}
