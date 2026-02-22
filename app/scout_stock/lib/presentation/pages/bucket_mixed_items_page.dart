import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scout_stock/domain/models/item.dart';
import 'package:scout_stock/presentation/pages/cart_page.dart';
import 'package:scout_stock/presentation/pages/scan_page.dart';
import 'package:scout_stock/presentation/widgets/admin_shell.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/presentation/widgets/hold_icon_button.dart';
import 'package:scout_stock/state/providers/cart_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

class BucketCatalogItem {
  const BucketCatalogItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.available,
  });

  final String id;
  final String name;
  final String emoji;
  final int available;
}

class BucketMixedItemsPage extends ConsumerStatefulWidget {
  const BucketMixedItemsPage({
    super.key,
    required this.bucketId,
    required this.bucketName,
    required this.items,
    this.cartTabIndex = 1,
  });

  final String bucketId;
  final String bucketName;
  final List<BucketCatalogItem> items;
  final int cartTabIndex;

  @override
  ConsumerState<BucketMixedItemsPage> createState() =>
      _BucketMixedItemsPageState();
}

class _BucketMixedItemsPageState extends ConsumerState<BucketMixedItemsPage> {
  final _searchCtrl = TextEditingController();

  final Map<String, int> _baseQty = {};

  @override
  void initState() {
    super.initState();
    _captureBaseline();
  }

  @override
  void didUpdateWidget(covariant BucketMixedItemsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bucketId != widget.bucketId) {
      _baseQty.clear();
      _captureBaseline();
    }
  }

  void _captureBaseline() {
    final cart = ref.read(cartProvider);
    final items = cart.items;
    for (final cat in widget.items) {
      final idx = items.indexWhere((x) => x.id == cat.id);
      _baseQty[cat.id] = idx == -1 ? 0 : items[idx].quantity;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Item? _findInCart(List<Item> items, String id) {
    for (final it in items) {
      if (it.id == id) return it;
    }
    return null;
  }

  void _openCart(BuildContext context) {
    final idx = AdminShellScope.maybeOf(context);
    if (idx != null) {
      idx.value = widget.cartTabIndex;
      Navigator.of(context).maybePop();
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartPage()));
  }

  void _applyDelta({
    required BucketCatalogItem cat,
    required int currentQty,
    required int delta,
  }) {
    final max = cat.available;
    final next = (currentQty + delta).clamp(0, max);

    final cart = ref.read(cartProvider.notifier);

    if (next == 0) {
      if (currentQty > 0) cart.remove(cat.id);
      return;
    }

    if (currentQty == 0) {
      cart.addItem(
        Item(
          id: cat.id,
          name: cat.name,
          emoji: cat.emoji,
          bucketId: widget.bucketId,
          bucketName: widget.bucketName,
          quantity: next,
          maxQuantity: max,
        ),
      );
      return;
    }

    final realDelta = next - currentQty;
    if (realDelta != 0) cart.bump(cat.id, realDelta);
  }

  int _addedFromThisPage(List<Item> cartItems) {
    int sum = 0;
    for (final cat in widget.items) {
      final current = _findInCart(cartItems, cat.id)?.quantity ?? 0;
      final base = _baseQty[cat.id] ?? 0;
      final diff = current - base;
      if (diff > 0) sum += diff;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final mediaTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 380;

    final cart = ref.watch(cartProvider);
    final cartItems = cart.items;

    final totalCartCount = cartItems.fold<int>(
      0,
      (sum, it) => sum + it.quantity,
    );

    final addedCount = _addedFromThisPage(cartItems);
    final showCta = addedCount > 0;

    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items
              .where(
                (it) =>
                    it.name.toLowerCase().contains(q) ||
                    it.id.toLowerCase().contains(q),
              )
              .toList(growable: false);

    final isEmpty = filtered.isEmpty;

    const ctaHeight = 70.0;
    const ctaPadding = EdgeInsets.fromLTRB(20, 10, 20, 18);

    final bottomBarFootprint = showCta
        ? (ctaHeight + ctaPadding.top + ctaPadding.bottom + safeBottom)
        : 0.0;

    final listBottomPadding = showCta
        ? (bottomBarFootprint + 12)
        : (safeBottom + 16);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SafeArea(
            top: false,
            child: Stack(
              children: [
                CustomScrollView(
                  cacheExtent: 900,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, mediaTop + 10, 20, 0),
                        child: BucketMixedHeader(
                          bucketId: widget.bucketId,
                          bucketName: widget.bucketName,
                          itemTypesCount: widget.items.length,
                          cartCount: totalCartCount,
                          onBack: () => Navigator.of(context).maybePop(),
                          onCart: () => _openCart(context),
                        ),
                      ),
                    ),

                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StickySearchDelegate(
                        height: 70,
                        child: Container(
                          color: AppColors.background,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                          alignment: Alignment.center,
                          child: _SearchCard(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                    ),

                    if (isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyBucketState(
                          query: _searchCtrl.text.trim(),
                          titleStyle: t.titleLarge,
                          bodyStyle: t.bodyLarge?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          listBottomPadding,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final cat = filtered[index];
                              final inCart = _findInCart(cartItems, cat.id);
                              final qty = inCart?.quantity ?? 0;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _MixedBucketItemCard(
                                  name: cat.name,
                                  emoji: cat.emoji,
                                  available: cat.available,
                                  quantity: qty,
                                  compact: compact,
                                  tokens: tokens,
                                  textTheme: t,
                                  onDelta: (d) => _applyDelta(
                                    cat: cat,
                                    currentQty: qty,
                                    delta: d,
                                  ),
                                ),
                              );
                            },
                            childCount: filtered.length,
                            addAutomaticKeepAlives: false,
                            addRepaintBoundaries: true,
                            addSemanticIndexes: false,
                          ),
                        ),
                      ),
                  ],
                ),

                if (showCta) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: bottomBarFootprint + 24,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.background.withValues(alpha: 0.0),
                              AppColors.background,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: GlowingActionButton(
                      label: 'ADD TO CART ($addedCount)',
                      icon: const Icon(Icons.shopping_cart_rounded),
                      height: ctaHeight,
                      padding: ctaPadding,
                      onPressed: () => _openCart(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BucketMixedHeader extends StatelessWidget {
  const BucketMixedHeader({
    super.key,
    required this.bucketId,
    required this.bucketName,
    required this.itemTypesCount,
    required this.cartCount,
    required this.onBack,
    required this.onCart,
  });

  final String bucketId;
  final String bucketName;
  final int itemTypesCount;
  final int cartCount;

  final VoidCallback onBack;
  final VoidCallback onCart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              splashRadius: 22,
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                bucketName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.headlineMedium,
              ),
            ),
            const SizedBox(width: 6),
            _CartIconButton(count: cartCount, onTap: onCart),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              bucketId,
              style: t.labelMedium?.copyWith(
                color: AppColors.primary,
                letterSpacing: 1.4,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mixed bucket | $itemTypesCount item types',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _CartIconButton extends StatelessWidget {
  const _CartIconButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkResponse(
          onTap: onTap,
          radius: 26,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.outline),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 10,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.shopping_cart_rounded,
              color: AppColors.ink,
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Container(
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
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.only(right: 16),
                hintText: 'Filter by name or scan...',
                hintStyle: t.bodyLarge?.copyWith(
                  color: const Color(0xFFB9C0C8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                controller.clear();
                onChanged('');
              },
              icon: const Icon(Icons.close_rounded),
              splashRadius: 20,
              tooltip: 'Clear',
            ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _StickySearchDelegate extends SliverPersistentHeaderDelegate {
  _StickySearchDelegate({required this.height, required this.child});

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: child),
        if (overlapsContent)
          Container(
            height: 1,
            color: AppColors.outline.withValues(alpha: 0.65),
          ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _StickySearchDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _MixedBucketItemCard extends StatelessWidget {
  const _MixedBucketItemCard({
    required this.name,
    required this.emoji,
    required this.available,
    required this.quantity,
    required this.compact,
    required this.tokens,
    required this.textTheme,
    required this.onDelta,
  });

  final String name;
  final String emoji;
  final int available;
  final int quantity;

  final bool compact;
  final AppTokens tokens;
  final TextTheme textTheme;

  final ValueChanged<int> onDelta;

  @override
  Widget build(BuildContext context) {
    final tile = compact ? 42.0 : 48.0;
    final emojiSize = compact ? 22.0 : 26.0;

    final shadow = tokens.cardShadow.isNotEmpty
        ? [
            tokens.cardShadow.first.copyWith(
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
          ]
        : const <BoxShadow>[];

    final disabled = available <= 0;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          boxShadow: shadow,
        ),
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                    border: Border.all(color: AppColors.outline),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    emoji,
                    style: TextStyle(fontSize: emojiSize, height: 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontSize: compact ? 15 : 16,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$available available',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 11.5 : 12,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : 12),
            _QtyStepperSelect(
              value: quantity,
              max: available,
              compact: compact,
              enabled: !disabled,
              onDelta: onDelta,
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyStepperSelect extends StatelessWidget {
  const _QtyStepperSelect({
    required this.value,
    required this.max,
    required this.compact,
    required this.enabled,
    required this.onDelta,
  });

  final int value;
  final int max;
  final bool compact;
  final bool enabled;
  final ValueChanged<int> onDelta;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final canMinus = enabled && value > 0;
    final canPlus = enabled && value < max;

    final height = compact ? 50.0 : 56.0;
    final btnSize = compact ? 40.0 : 44.0;
    final iconSize = compact ? 20.0 : 22.0;

    final disabledFg = AppColors.muted.withValues(alpha: 0.45);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          HoldIconButton(
            enabled: canMinus,
            maxCount: max,
            icon: Icons.remove_rounded,
            iconColor: canMinus ? AppColors.primary : disabledFg,
            fill: AppColors.background,
            border: Colors.transparent,
            width: btnSize,
            height: btnSize,
            iconSize: iconSize,
            radius: tokens.radiusLg,
            onTap: canMinus ? () => onDelta(-1) : null,
            onHoldTick: canMinus ? (step) => onDelta(-step) : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: (compact ? t.titleLarge : t.headlineSmall)?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'of $max available',
                    style: t.bodySmall?.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          HoldIconButton(
            enabled: canPlus,
            maxCount: max,
            icon: Icons.add_rounded,
            iconColor: canPlus ? AppColors.primary : disabledFg,
            fill: AppColors.background,
            border: Colors.transparent,
            width: btnSize,
            height: btnSize,
            iconSize: iconSize,
            radius: tokens.radiusLg,
            onTap: canPlus ? () => onDelta(1) : null,
            onHoldTick: canPlus ? (step) => onDelta(step) : null,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _EmptyBucketState extends StatelessWidget {
  const _EmptyBucketState({
    required this.query,
    this.titleStyle,
    this.bodyStyle,
  });

  final String query;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    final title = query.isEmpty ? 'No items in this bucket' : 'No results';
    final subtitle = query.isEmpty
        ? 'This bucket is empty (or not loaded).\nTry scanning another bucket.'
        : 'Try a different keyword.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.outline),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.muted,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: titleStyle?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: bodyStyle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
