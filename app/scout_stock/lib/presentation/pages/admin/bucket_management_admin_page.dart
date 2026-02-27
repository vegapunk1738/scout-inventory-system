import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/router/app_routes.dart';
import 'package:scout_stock/presentation/pages/admin/bucket_upsert_page.dart';

enum BucketStockState { fullyStocked, inUse, outOfStock }

class BucketSummary {
  const BucketSummary({
    required this.id,
    required this.name,
    required this.itemTypeCount,
    required this.lastActivityAt,
    required this.state,
    this.contentsPreview = const [],
    this.tags = const [],
  });

  /// Human-readable bucket ID (e.g. SSB-BKT-042).
  final String id;

  final String name;

  /// Count of distinct item types (not global stock).
  final int itemTypeCount;

  final DateTime lastActivityAt;

  final BucketStockState state;

  /// Small preview for search matching / hinting contents.
  final List<String> contentsPreview;

  final List<String> tags;
}

class BucketManagementAdminPage extends StatefulWidget {
  const BucketManagementAdminPage({super.key});

  @override
  State<BucketManagementAdminPage> createState() =>
      _BucketManagementAdminPageState();
}

class _BucketManagementAdminPageState extends State<BucketManagementAdminPage> {
  static final PdfPageFormat _labelFormat = PdfPageFormat(
    4 * PdfPageFormat.inch,
    2 * PdfPageFormat.inch,
    marginAll: 0,
  );

  final _searchCtrl = TextEditingController();
  String _query = '';

  bool _printing = false;

  late final List<BucketSummary> _seed = List<BucketSummary>.of(_mockBuckets())
    ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }


  Future<void> _openCreateBucket() async {
    final res = await context.push<Map<String, dynamic>>(AppRoutes.adminBucketCreate);
    if (!mounted) return;
    if (res == null) return;

    final contents = (res['contents'] as List?) ?? const [];
    final now = DateTime.now();

    setState(() {
      _seed.insert(
        0,
        BucketSummary(
          id: (res['barcode'] as String?) ?? 'SSB---000',
          name: (res['name'] as String?) ?? 'New Bucket',
          itemTypeCount: contents.length,
          lastActivityAt: now,
          state: contents.isEmpty ? BucketStockState.outOfStock : BucketStockState.fullyStocked,
          contentsPreview: contents
              .map((e) => (e as Map)['name']?.toString() ?? '')
              .where((s) => s.trim().isNotEmpty)
              .take(3)
              .toList(),
        ),
      );
    });

    _showSnack('Created ${(res['name'] as String?) ?? 'bucket'}');
  }

  Future<void> _openEditBucket(BucketSummary b) async {
    final seeds = b.contentsPreview
        .map((n) => BucketContentSeed(name: n, emoji: '📦', quantity: 1))
        .toList();

    final args = BucketUpsertArgs(
      barcode: b.id,
      name: b.name,
      emoji: '🪣',
      contents: seeds,
    );

    final res = await context.push<Map<String, dynamic>>(
      AppRoutes.adminBucketEdit(b.id),
      extra: args,
    );

    if (!mounted) return;
    if (res == null) return;

    final contents = (res['contents'] as List?) ?? const [];
    final now = DateTime.now();

    setState(() {
      final idx = _seed.indexWhere((x) => x.id == b.id);
      if (idx == -1) return;

      _seed[idx] = BucketSummary(
        id: (res['barcode'] as String?) ?? b.id,
        name: (res['name'] as String?) ?? b.name,
        itemTypeCount: contents.length,
        lastActivityAt: now,
        state: contents.isEmpty ? BucketStockState.outOfStock : BucketStockState.fullyStocked,
        tags: _seed[idx].tags,
        contentsPreview: contents
            .map((e) => (e as Map)['name']?.toString() ?? '')
            .where((s) => s.trim().isNotEmpty)
            .take(3)
            .toList(),
      );
    });

    _showSnack('Saved ${(res['name'] as String?) ?? b.name}');
  }

  Future<void> _confirmDelete(BucketSummary b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete bucket?'),
        content: Text(
          'This will remove "${b.name}" (#${b.id}).\n\n'
          'Inventory history stays in the audit log, but the bucket will no longer be available to scan.',
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

    if (!mounted) return;
    if (ok != true) return;

    setState(() => _seed.removeWhere((x) => x.id == b.id));
    _showSnack('Deleted ${b.name} (#${b.id})');
  }

  Future<void> _printBucketLabel(BucketSummary bucket) async {
    if (_printing) return;

    final id = bucket.id.trim();
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

          // Compute a barcode height that always fits.
          // (Keeps the ID line visible even on 2" tall labels.)
          final barcodeH =
              (format.height - 78) // reserve space for texts + padding
                  .clamp(44.0, 66.0)
                  .toDouble();

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
      _showSnack('Could not print label for ${bucket.id}');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);
    final mediaTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final q = _query.trim().toLowerCase();
    final items = q.isEmpty
        ? _seed
        : _seed
              .where((b) {
                if (b.name.toLowerCase().contains(q)) return true;
                if (b.id.toLowerCase().contains(q)) return true;
                if (b.tags.any((x) => x.toLowerCase().contains(q))) return true;
                if (b.contentsPreview.any((x) => x.toLowerCase().contains(q))) {
                  return true;
                }
                return false;
              })
              .toList(growable: false);

    final isEmpty = items.isEmpty;

    // Match AdminShell bottom nav footprint (height 78 + padding 12)
    const navHeight = 78.0;
    const navPad = 12.0;
    final bottomFootprint = safeBottom + navHeight + navPad + 10;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SafeArea(
            top: false,
            child: CustomScrollView(
              cacheExtent: 900,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, mediaTop + 10, 20, 0),
                    child: _ManageHeader(
                      onAdd: _openCreateBucket,
                    ),
                  ),
                ),

                // Sticky search (same size/style/position as Users & Activity)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyHeaderDelegate(
                    height: 70,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: _SearchCard(
                        controller: _searchCtrl,
                        hintText: 'Search ID, tag, or contents…',
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
                      bodyStyle: t.bodyLarge?.copyWith(color: AppColors.muted),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
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

                SliverToBoxAdapter(child: SizedBox(height: bottomFootprint)),
              ],
            ),
          ),

          // Small UX safety: block double-taps while print dialog is preparing.
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
                      borderRadius: BorderRadius.circular(tokens.radiusLg),
                      boxShadow: tokens.cardShadow,
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Preparing label…',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
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
        // Match Users page circular "New" button (not the design mock)
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

  final BucketSummary bucket;
  final double radiusXl;

  final VoidCallback onEdit;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    final timeText = _formatRelative(bucket.lastActivityAt);

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
                      _StockPill(state: bucket.state),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('#${bucket.id}', style: idStyle),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('${bucket.itemTypeCount} Items', style: metaStyle),
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
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
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

List<BucketSummary> _mockBuckets() {
  final now = DateTime.now();
  return [
    BucketSummary(
      id: 'SSB-BKT-042',
      name: 'Patrol Box A',
      itemTypeCount: 12,
      lastActivityAt: now.subtract(const Duration(hours: 2)),
      state: BucketStockState.fullyStocked,
      tags: const ['patrol', 'box'],
      contentsPreview: const ['Flags', 'Rope', 'Tape'],
    ),
    BucketSummary(
      id: 'SSB-BKT-088',
      name: 'Tools Kit #3',
      itemTypeCount: 8,
      lastActivityAt: now.subtract(const Duration(minutes: 45)),
      state: BucketStockState.inUse,
      tags: const ['tools'],
      contentsPreview: const ['Pliers', 'Screwdriver', 'Tape'],
    ),
    BucketSummary(
      id: 'SSB-BKT-012',
      name: 'First Aid Base',
      itemTypeCount: 45,
      lastActivityAt: now.subtract(const Duration(days: 1)),
      state: BucketStockState.fullyStocked,
      tags: const ['medical', 'first-aid'],
      contentsPreview: const ['Bandages', 'Gloves', 'Alcohol swabs'],
    ),
    BucketSummary(
      id: 'SSB-BKT-031',
      name: 'Craft Supplies',
      itemTypeCount: 0,
      lastActivityAt: now.subtract(const Duration(days: 3)),
      state: BucketStockState.outOfStock,
      tags: const ['craft'],
      contentsPreview: const ['Paper', 'Markers'],
    ),
  ];
}
