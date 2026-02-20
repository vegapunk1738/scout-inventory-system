import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/domain/models/item.dart';
import 'package:scout_stock/presentation/widgets/admin_shell.dart';
import 'package:scout_stock/presentation/widgets/checkout_result_dialog.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.only(left: 10.0),
          child: Text('Review Cart', style: t.titleLarge),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 30.0),
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
      body: Column(
        children: [
          Expanded(
            child: isEmpty
                ? _EmptyCart(
                    emojiBase: emojiBase,
                    titleStyle: t.titleLarge,
                    bodyStyle: t.bodyLarge?.copyWith(color: AppColors.muted),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
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
                        onMinus: () =>
                            ref.read(cartProvider.notifier).decrement(item.id),
                        onPlus: () =>
                            ref.read(cartProvider.notifier).increment(item.id),
                        onRemove: () =>
                            ref.read(cartProvider.notifier).remove(item.id),
                      );
                    },
                  ),
          ),
          GlowingActionButton(
            label: 'Confirm Checkout ($totalItems)',
            icon: const Icon(Icons.check_rounded),
            loading: _submitting,
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
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
  });

  final Item item;
  final bool compact;
  final AppTokens tokens;
  final TextTheme textTheme;
  final TextStyle emojiBase;

  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tile = compact ? 48.0 : 54.0;
    final emojiSize = compact ? 24.0 : 28.0;

    final shadow = tokens.cardShadow.isNotEmpty
        ? [
            tokens.cardShadow.first.copyWith(
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ]
        : const <BoxShadow>[];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        boxShadow: shadow,
      ),
      padding: EdgeInsets.all(compact ? 12 : 14),
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
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: compact ? 16 : 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${item.bucketName} | ${item.bucketId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 12 : 13,
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
          const SizedBox(height: 12),
          _QtyStepperBig(
            value: item.quantity,
            max: item.maxQuantity,
            compact: compact,
            onMinus: onMinus,
            onPlus: onPlus,
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- Big Stepper ----------------------------- */

class _QtyStepperBig extends StatelessWidget {
  const _QtyStepperBig({
    required this.value,
    required this.max,
    required this.compact,
    required this.onMinus,
    required this.onPlus,
  });

  final int value;
  final int max;
  final bool compact;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final canMinus = value > 1;
    final canPlus = value < max;

    final height = compact ? 56.0 : 62.0;
    final btnSize = compact ? 46.0 : 50.0;
    final iconSize = compact ? 22.0 : 24.0;

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
          _StepIconButton(
            icon: Icons.remove_rounded,
            size: btnSize,
            iconSize: iconSize,
            enabled: canMinus,
            onTap: canMinus ? onMinus : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: (compact ? t.headlineSmall : t.headlineMedium)
                        ?.copyWith(fontWeight: FontWeight.w900, height: 1),
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
          _StepIconButton(
            icon: Icons.add_rounded,
            size: btnSize,
            iconSize: iconSize,
            enabled: canPlus,
            onTap: canPlus ? onPlus : null,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _StepIconButton extends StatelessWidget {
  const _StepIconButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final fg = enabled
        ? AppColors.primary
        : AppColors.muted.withValues(alpha: 0.45);

    return Semantics(
      button: true,
      enabled: enabled,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: iconSize, color: fg),
        ),
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
    final box = compact ? 38.0 : 42.0;
    final iconSize = compact ? 20.0 : 22.0;

    return InkResponse(
      onTap: onTap,
      radius: 24,
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
            Text('🛒', style: emojiBase.copyWith(fontSize: 56)),
            const SizedBox(height: 12),
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
