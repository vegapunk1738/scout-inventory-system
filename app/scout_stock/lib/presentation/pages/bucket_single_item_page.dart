import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scout_stock/domain/models/item.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/presentation/widgets/hold_icon_button.dart';
import 'package:scout_stock/state/providers/cart_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

class BucketItemPage extends ConsumerStatefulWidget {
  const BucketItemPage({super.key, required this.barcode});
  final String barcode;

  @override
  ConsumerState<BucketItemPage> createState() => _BucketItemPageState();
}

class _BucketItemPageState extends ConsumerState<BucketItemPage> {
  final int bucketNumber = 42;
  final String bucketName = 'Patrol Box Alpha';

  final String itemName = 'Propane Canisters';
  final String sku = 'OUT-PRO-16OZ';

  final int maxCount = 1000; 
  int qty = 12;

  bool _loading = false;

  void _applyDelta(int delta) {
    if (!mounted) return;

    final next = (qty + delta).clamp(0, maxCount);
    if (next == qty) return;

    HapticFeedback.selectionClick();
    setState(() => qty = next);
  }

  void _decTap() => _applyDelta(-1);
  void _incTap() => _applyDelta(1);

  Future<void> _addToCart() async {
    if (_loading || qty <= 0) return;
    setState(() => _loading = true);

    final bucketId = Item.formatBucketId(
      bucketCode3: 'PBX',
      sequence: bucketNumber,
    );
    final itemId = Item.formatItemId(itemCode3: 'PRP', sequence: 1);

    final item = Item(
      id: itemId,
      name: itemName,
      bucketId: bucketId,
      bucketName: bucketName,
      quantity: qty,
      maxQuantity: maxCount,
      emoji: '⛽',
    );

    ref.read(cartProvider.notifier).addItem(item);

    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!mounted) return;
    setState(() => _loading = false);

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final canDec = qty > 0;
    final canInc = qty < maxCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(leading: const BackButton()),
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        'BUCKET #$bucketNumber',
                        style: t.labelMedium?.copyWith(
                          color: AppColors.primary,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        bucketName,
                        textAlign: TextAlign.center,
                        style: t.headlineMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(tokens.radiusXl),
                      boxShadow: tokens.cardShadow,
                    ),
                    child: Center(
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Icon(
                          Icons.propane_tank_outlined,
                          size: 44,
                          color: AppColors.primary.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    itemName,
                    textAlign: TextAlign.center,
                    style: t.headlineMedium?.copyWith(fontSize: 34),
                  ),
                ),
                const SizedBox(height: 40),
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: t.displaySmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                      children: [
                        TextSpan(
                          text: 'x',
                          style: t.headlineMedium?.copyWith(
                            color: AppColors.ink.withValues(alpha: 0.30),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const TextSpan(text: ' '),
                        TextSpan(text: '$qty'),
                        TextSpan(
                          text: '/$maxCount',
                          style: t.headlineMedium?.copyWith(
                            color: AppColors.ink.withValues(alpha: 0.35),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Hold + / − to go faster',
                    style: t.bodyMedium?.copyWith(
                      color: AppColors.ink.withValues(alpha: 0.30),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 110),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(tokens.radiusXl),
                border: Border.all(color: AppColors.outline),
                boxShadow: tokens.cardShadow,
              ),
              child: Row(
                children: [
                  HoldIconButton(
                    enabled: canDec,
                    maxCount: maxCount,
                    fill: const Color(0xFFF8FAFC),
                    border: AppColors.outline,
                    icon: Icons.remove,
                    iconColor: canDec
                        ? AppColors.ink.withValues(alpha: 0.70)
                        : AppColors.ink.withValues(alpha: 0.25),
                    width: 64,
                    height: 62,
                    iconSize: 30,
                    radius: tokens.radiusXl,
                    onTap: canDec ? _decTap : null,
                    onHoldTick: canDec ? (step) => _applyDelta(-step) : null,
                  ),

                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 62,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: Center(
                        child: Text(
                          '$qty / $maxCount',
                          style: t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  HoldIconButton(
                    enabled: canInc,
                    maxCount: maxCount,
                    fill: AppColors.primary,
                    border: Colors.transparent,
                    glow: true,
                    icon: Icons.add,
                    iconColor: Colors.white,
                    width: 64,
                    height: 62,
                    iconSize: 30,
                    radius: tokens.radiusXl,
                    onTap: canInc ? _incTap : null,
                    onHoldTick: canInc ? (step) => _applyDelta(step) : null,
                  ),
                ],
              ),
            ),
          ),
          GlowingActionButton(
            label: 'ADD TO CART',
            icon: const Icon(Icons.shopping_cart_rounded),
            loading: _loading,
            onPressed: qty > 0 ? _addToCart : null,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            height: 70,
          ),
        ],
      ),
    );
  }
}