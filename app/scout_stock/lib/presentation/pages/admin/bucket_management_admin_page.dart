import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/bucket.dart';
import 'package:scout_stock/presentation/widgets/app_toast.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/state/providers/buckets_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/router/app_routes.dart';
import 'package:scout_stock/presentation/pages/admin/bucket_upsert_page.dart';

class BucketManagementAdminPage extends ConsumerStatefulWidget {
  const BucketManagementAdminPage({super.key});

  @override
  ConsumerState<BucketManagementAdminPage> createState() =>
      _BucketManagementAdminPageState();
}

class _BucketManagementAdminPageState
    extends ConsumerState<BucketManagementAdminPage> {
  static final PdfPageFormat _labelFormat = PdfPageFormat(
    4 * PdfPageFormat.inch,
    2 * PdfPageFormat.inch,
    marginAll: 0,
  );

  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _printing = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Error helper — mirrors users_page._showError exactly ──────────────

  void _showError(Object e, {required String action}) {
    if (e is ApiException && e.hasFieldErrors) {
      final toast = AppToast.of(context);
      for (final fe in e.fieldErrors) {
        toast.show(AppToastData.error(
          title: fe.label,
          subtitle: fe.message,
          duration: const Duration(seconds: 6),
        ));
      }
      return;
    }

    final msg = e is ApiException
        ? e.message
        : 'Something went wrong. Please try again.';
    AppToast.of(context).show(AppToastData.error(
      title: action,
      subtitle: msg,
      duration: const Duration(seconds: 5),
    ));
  }

  // ── Create ────────────────────────────────────────────────────────────

  Future<void> _openCreateBucket() async {
    final res = await context.push<Map<String, dynamic>>(
      AppRoutes.adminBucketCreate,
    );
    if (!mounted || res == null) return;

    final name = (res['name'] ?? '').toString();
    final abbreviation = (res['abbreviation'] ?? '').toString();
    final contents =
        (res['contents'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    try {
      final created = await ref.read(bucketsProvider.notifier).createBucket(
            name: name,
            abbreviation: abbreviation,
            items: contents,
          );
      if (!mounted) return;

      final itemCount = created.items.length;
      final itemLabel = itemCount == 1 ? '1 item' : '$itemCount items';

      AppToast.of(context).show(AppToastData.success(
        title: '$name created',
        subtitle: '#${created.barcode}  ·  $itemLabel',
      ));
    } catch (e) {
      if (!mounted) return;
      _showError(e, action: 'Could not create $name');
    }
  }

  // ── Edit ──────────────────────────────────────────────────────────────

  Future<void> _openEditBucket(Bucket bucket) async {
    final seeds = bucket.items
        .map((i) => BucketContentSeed(
              id: i.id,
              name: i.name,
              emoji: i.emoji,
              quantity: i.quantity,
              borrowed: i.borrowed,
            ))
        .toList();

    final args = BucketUpsertArgs(
      bucketId: bucket.id,
      barcode: bucket.barcode,
      name: bucket.name,
      contents: seeds,
    );

    final res = await context.push<Map<String, dynamic>>(
      AppRoutes.adminBucketEdit(bucket.barcode),
      extra: args,
    );

    if (!mounted || res == null) return;

    final newName = (res['name'] as String?) ?? bucket.name;
    final contents =
        (res['contents'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    try {
      final updated = await ref.read(bucketsProvider.notifier).updateBucket(
            bucket.id,
            name: newName,
            items: contents,
          );
      if (!mounted) return;

      // Build descriptive subtitle about what changed.
      final changes = <String>[];
      if (newName != bucket.name) changes.add('${bucket.name} → $newName');
      if (updated.items.length != bucket.items.length) {
        changes.add('${bucket.items.length} → ${updated.items.length} items');
      } else {
        changes.add('Items updated');
      }

      final displayName = newName != bucket.name ? newName : bucket.name;
      AppToast.of(context).show(AppToastData.success(
        title: '$displayName updated',
        subtitle: changes.join('  ·  '),
      ));
    } catch (e) {
      if (!mounted) return;
      _showError(e, action: 'Could not update ${bucket.name}');
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(Bucket bucket) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete bucket?'),
        content: Text(
          'This will remove "${bucket.name}" (#${bucket.barcode}).\n\n'
          'Inventory history stays in the audit log, but the bucket will '
          'no longer be available to scan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD92D20),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || ok != true) return;

    try {
      await ref.read(bucketsProvider.notifier).deleteBucket(bucket.id);
      if (!mounted) return;

      final itemLabel =
          bucket.items.length == 1 ? '1 item' : '${bucket.items.length} items';
      AppToast.of(context).show(AppToastData.success(
        title: '${bucket.name} removed',
        subtitle: '#${bucket.barcode}  ·  $itemLabel cleared',
      ));
    } catch (e) {
      if (!mounted) return;
      _showError(e, action: 'Could not delete ${bucket.name}');
    }
  }

  // ── Print ─────────────────────────────────────────────────────────────

  Future<void> _printBucketLabel(Bucket bucket) async {
    if (_printing) return;

    final id = bucket.barcode.trim();
    String safeFileName(String s) {
      final cleaned = s.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ');
      return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: safeFileName(bucket.name),
        format: _labelFormat,
        onLayout: (format) async {
          final doc = pw.Document();

          final barcodeH =
              (format.height - 78).clamp(44.0, 66.0).toDouble();

          doc.addPage(
            pw.Page(
              pageFormat: format,
              build: (_) {
                return pw.Container(
                  color: PdfColors.white,
                  padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        child: pw.Text(
                          bucket.name,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: id,
                        drawText: false,
                        width: double.infinity,
                        height: barcodeH,
                      ),
                      pw.SizedBox(height: 6),
                      pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        child: pw.Text(
                          id,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );

          return doc.save();
        },
      );
    } catch (_) {
      debugPrint('Could not print label for ${bucket.barcode}');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);
    final mediaTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final bucketsAsync = ref.watch(bucketsProvider);

    // Match AdminShell bottom nav footprint
    const navHeight = 78.0;
    const navPad = 12.0;
    final bottomFootprint = safeBottom + navHeight + navPad + 10;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          bucketsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.muted),
                  const SizedBox(height: 12),
                  Text('Failed to load buckets', style: t.titleMedium),
                  const SizedBox(height: 4),
                  Text('$err',
                      style: t.bodySmall?.copyWith(color: AppColors.muted)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(bucketsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (allBuckets) {
              final q = _query.trim().toLowerCase();
              final items = q.isEmpty
                  ? allBuckets
                  : allBuckets.where((b) {
                      if (b.name.toLowerCase().contains(q)) return true;
                      if (b.barcode.toLowerCase().contains(q)) return true;
                      if (b.items.any(
                          (i) => i.name.toLowerCase().contains(q))) {
                        return true;
                      }
                      return false;
                    }).toList(growable: false);

              final isEmpty = items.isEmpty;

              return SafeArea(
                top: false,
                child: CustomScrollView(
                  cacheExtent: 900,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, mediaTop + 10, 20, 0),
                        child: _ManageHeader(onAdd: _openCreateBucket),
                      ),
                    ),

                    // Sticky search
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StickyHeaderDelegate(
                        height: 70,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                          child: _SearchCard(
                            controller: _searchCtrl,
                            hintText: 'Search ID, name, or contents…',
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'ALL BUCKETS',
                                style: t.labelMedium?.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            Text(
                              'STATUS',
                              style: t.labelMedium?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyBucketsState(
                          query: q,
                          emojiBase: emojiBase.copyWith(fontSize: 54),
                          titleStyle: t.titleLarge,
                          bodyStyle:
                              t.bodyLarge?.copyWith(color: AppColors.muted),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        sliver: SliverList(
                          delegate:
                              SliverChildBuilderDelegate((context, index) {
                            final b = items[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: RepaintBoundary(
                                child: _BucketCard(
                                  bucket: b,
                                  radiusXl: tokens.radiusXl,
                                  onEdit: () => _openEditBucket(b),
                                  onPrint: () => _printBucketLabel(b),
                                  onDelete: () => _confirmDelete(b),
                                ),
                              ),
                            );
                          }, childCount: items.length),
                        ),
                      ),

                    SliverToBoxAdapter(
                        child: SizedBox(height: bottomFootprint)),
                  ],
                ),
              );
            },
          ),

          // Print overlay
          if (_printing)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: false,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.05),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(tokens.radiusLg),
                      boxShadow: tokens.cardShadow,
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Preparing label…',
                          style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private widgets
// ═══════════════════════════════════════════════════════════════════════════

class _ManageHeader extends StatelessWidget {
  const _ManageHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bucket Management', style: t.titleLarge),
              const SizedBox(height: 4),
              Text(
                'ADMIN VIEW',
                style: t.labelMedium?.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: tokens.glowShadow,
          ),
          child: SizedBox(
            width: 42,
            height: 42,
            child: IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              splashRadius: 28,
              tooltip: 'New bucket',
              style: IconButton.styleFrom(
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BucketCard extends StatelessWidget {
  const _BucketCard({
    required this.bucket,
    required this.radiusXl,
    required this.onEdit,
    required this.onPrint,
    required this.onDelete,
  });

  final Bucket bucket;
  final double radiusXl;
  final VoidCallback onEdit;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    final timeText = _formatRelative(DateTime.parse(bucket.createdAt));

    final nameStyle = t.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    );

    final idStyle = t.bodyMedium?.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w700,
    );

    final metaStyle = t.bodyMedium?.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w700,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusXl),
        border: Border.all(color: AppColors.outline),
        boxShadow: tokens.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radiusXl),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          bucket.name,
                          style: nameStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StockPill(state: bucket.stockState),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('#${bucket.barcode}', style: idStyle),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        '${bucket.items.length} Items',
                        style: metaStyle,
                      ),
                      const Spacer(),
                      Text(timeText, style: metaStyle),
                    ],
                  ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.outline),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _CardActionButton(label: 'Edit', onPressed: onEdit),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CardActionButton(
                      label: 'Print Label',
                      onPressed: onPrint,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CardActionButton(
                      label: 'Delete',
                      onPressed: onDelete,
                      variant: _CardActionVariant.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CardActionVariant { neutral, danger }

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.label,
    required this.onPressed,
    this.variant = _CardActionVariant.neutral,
  });

  final String label;
  final VoidCallback onPressed;
  final _CardActionVariant variant;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    final bg = variant == _CardActionVariant.danger
        ? const Color(0xFFFEE4E2)
        : const Color(0xFFF2F4F7);

    final fg = variant == _CardActionVariant.danger
        ? const Color(0xFFD92D20)
        : const Color(0xFF475467);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        child: SizedBox(
          height: 46,
          child: Center(
            child: Text(
              label,
              style: t.titleMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill({required this.state});

  final BucketStockState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    late final Color bg;
    late final Color border;
    late final Color fg;
    late final String text;

    switch (state) {
      case BucketStockState.fullyStocked:
        bg = AppColors.successBg;
        border = const Color(0xFFB7E4C7);
        fg = AppColors.primary;
        text = 'In Stock';
        break;
      case BucketStockState.inUse:
        bg = AppColors.warningBg;
        border = const Color(0xFFFBD38D);
        fg = const Color(0xFF8A5B00);
        text = 'In Use';
        break;
      case BucketStockState.outOfStock:
        bg = const Color(0xFFFFE8E8);
        border = const Color(0xFFFECACA);
        fg = const Color(0xFFB42318);
        text = 'Out of Stock';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: t.bodyMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.onChanged,
    required this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          boxShadow: tokens.cardShadow,
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search_rounded, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: t.bodyLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.only(right: 16),
                  hintText: hintText,
                  hintStyle: t.bodyLarge?.copyWith(
                    color: const Color(0xFFB9C0CC),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _EmptyBucketsState extends StatelessWidget {
  const _EmptyBucketsState({
    required this.query,
    required this.emojiBase,
    required this.titleStyle,
    required this.bodyStyle,
  });

  final String query;
  final TextStyle emojiBase;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    final title = query.isEmpty ? 'No buckets yet' : 'No buckets found';
    final subtitle = query.isEmpty
        ? 'Create your first bucket to start tracking inventory'
        : 'Try a different keyword';
    final emoji = query.isEmpty ? '🪣' : '🔎';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: emojiBase),
            const SizedBox(height: 10),
            Text(title, style: titleStyle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: bodyStyle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _formatRelative(DateTime dt) {
  final now = DateTime.now();
  final d = now.difference(dt);

  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';

  final weeks = (d.inDays / 7).floor();
  if (weeks < 5) return '${weeks}w ago';

  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}