import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/domain/models/item.dart';
import 'package:scout_stock/presentation/widgets/admin_shell.dart';
import 'package:scout_stock/presentation/widgets/checkout_result_dialog.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/presentation/widgets/hold_icon_button.dart';
import 'package:scout_stock/state/providers/cart_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  bool _submitting = false;

  Future<({bool ok, String? txnId, String? error})> _checkoutRequest() async {
    // Replace with your real API call.
    await Future.delayed(const Duration(milliseconds: 650));

    final ok = Random().nextBool(); // demo
    if (ok) return (ok: true, txnId: '#CH-89204-X', error: null);
    return (ok: false, txnId: null, error: 'E-CHK-500');
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final items = cart.items;

    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final isEmpty = items.isEmpty;

    final totalItems = items.fold<int>(0, (sum, item) => sum + item.quantity);

    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 380;

    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);

    final safeBottom = MediaQuery.of(context).padding.bottom;

    final btnHeight = compact ? 62.0 : 66.0;
    final btnPadTop = compact ? 8.0 : 10.0;
    final btnPadBottom = compact ? 10.0 : 12.0;

    // Total vertical space the bottom button area occupies (including SafeArea).
    final bottomBarFootprint =
        btnHeight + btnPadTop + btnPadBottom + safeBottom;

    // Let the list scroll behind the button, but allow the last item to scroll above it.
    final listBottomPadding = bottomBarFootprint + 12;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text('Review Cart', style: t.titleLarge),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 23.0),
            child: IconButton(
              tooltip: cart.undoCount > 0 ? 'Undo (${cart.undoCount})' : 'Undo',
              onPressed: cart.canUndo
                  ? () => ref.read(cartProvider.notifier).undoRemove()
                  : null,
              icon: const Icon(Icons.undo_rounded),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          Positioned.fill(
            child: isEmpty
                ? _EmptyCart(
                    emojiBase: emojiBase,
                    titleStyle: t.titleLarge,
                    bodyStyle: t.bodyLarge?.copyWith(color: AppColors.muted),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 14,
                      compact ? 12 : 14,
                      compact ? 12 : 14,
                      listBottomPadding,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: compact ? 10 : 12),
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return _CartItemCard(
                        item: item,
                        compact: compact,
                        tokens: tokens,
                        textTheme: t,
                        emojiBase: emojiBase,
                        onRemove: () =>
                            ref.read(cartProvider.notifier).remove(item.id),
                        onDelta: (d) =>
                            ref.read(cartProvider.notifier).bump(item.id, d),
                      );
                    },
                  ),
          ),

          // Soft scrim so content behind the button doesn’t look harsh.
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
              label: 'Confirm Checkout ($totalItems)',
              icon: const Icon(Icons.check_rounded),
              loading: _submitting,
              height: btnHeight,
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 16,
                btnPadTop,
                compact ? 14 : 16,
                btnPadBottom,
              ),
              onPressed: isEmpty
                  ? null
                  : () async {
                      setState(() => _submitting = true);
                      try {
                        final res = await _checkoutRequest();
                        if (!mounted) return;

                        if (res.ok) {
                          await showCheckoutResultDialog(
                            context,
                            child: CheckoutResultDialog.success(
                              transactionId: res.txnId!,
                              onFinish: () {
                                ref.read(cartProvider.notifier).clear();
                                final idx = AdminShellScope.maybeOf(context);
                                if (idx != null) idx.value = 0;
                              },
                            ),
                          );
                        } else {
                          await showCheckoutResultDialog(
                            context,
                            child: CheckoutResultDialog.failure(
                              errorCode: res.error,
                              onRetry: () {},
                              onClose: () {},
                            ),
                            barrierDismissible: true,
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _submitting = false);
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- Card Row ----------------------------- */

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.compact,
    required this.tokens,
    required this.textTheme,
    required this.emojiBase,
    required this.onRemove,
    required this.onDelta,
  });

  final Item item;
  final bool compact;
  final AppTokens tokens;
  final TextTheme textTheme;
  final TextStyle emojiBase;

  final VoidCallback onRemove;
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

    return Container(
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
                  item.emoji,
                  style: emojiBase.copyWith(fontSize: emojiSize),
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
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: compact ? 15 : 16,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.bucketName} | ${item.bucketId}',
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
              const SizedBox(width: 8),
              _TrashPillButton(compact: compact, onTap: onRemove),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          _QtyStepperBig(
            value: item.quantity,
            max: item.maxQuantity,
            compact: compact,
            onDelta: onDelta,
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- Big Stepper (tap + hold) ----------------------------- */

class _QtyStepperBig extends StatelessWidget {
  const _QtyStepperBig({
    required this.value,
    required this.max,
    required this.compact,
    required this.onDelta,
  });

  final int value;
  final int max;
  final bool compact;
  final ValueChanged<int> onDelta;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final canMinus = value > 1;
    final canPlus = value < max;

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

          // MINUS (tap + hold)
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

          // PLUS (tap + hold)
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

class _TrashPillButton extends StatelessWidget {
  const _TrashPillButton({required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final box = compact ? 34.0 : 38.0;
    final iconSize = compact ? 18.0 : 20.0;

    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: box,
        height: box,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          border: Border.all(color: AppColors.outline),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.delete_outline_rounded,
          size: iconSize,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

/* ----------------------------- Empty state ----------------------------- */

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.emojiBase, this.titleStyle, this.bodyStyle});

  final TextStyle emojiBase;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🛒', style: emojiBase.copyWith(fontSize: 54)),
            const SizedBox(height: 10),
            Text(
              'Your cart is empty',
              style: titleStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a bucket and add items to checkout',
              style: bodyStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
