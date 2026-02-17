import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/widgets/admin_shell.dart';
import 'dart:math';
import 'package:scout_stock/widgets/checkout_result_dialog.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _submitting = false;

  Future<({bool ok, String? txnId, String? error})> _checkoutRequest() async {
    // Replace with your real API call.
    await Future.delayed(const Duration(milliseconds: 650));

    final ok = Random().nextBool(); // demo
    if (ok) return (ok: true, txnId: '#CH-89204-X', error: null);
    return (ok: false, txnId: null, error: 'E-CHK-500');
  }

  final List<_CartLine> _lines = [
    _CartLine(
      itemName: 'Coleman 4-Person Tent',
      bucketName: 'Tents Bucket',
      qty: 1,
      maxQty: 4,
      emoji: '🏕️',
      emojiBg: AppColors.successBg,
    ),
    _CartLine(
      itemName: 'Heavy Duty Stakes',
      bucketName: 'Stakes Bucket',
      qty: 4,
      maxQty: 8,
      emoji: '📌',
      emojiBg: AppColors.warningBg,
    ),
    _CartLine(
      itemName: 'Propane Stove (2 Burner)',
      bucketName: 'Stoves Bucket',
      qty: 1,
      maxQty: 4,
      emoji: '🔥',
      emojiBg: AppColors.infoBg,
    ),
    _CartLine(
      itemName: 'Mess Kit (Full Set)',
      bucketName: 'Mess Kits Bucket',
      qty: 4,
      maxQty: 4,
      emoji: '🍲',
      emojiBg: const Color(0xFFFFE8EE),
    ),
  ];

  int get _totalItems => _lines.fold<int>(0, (sum, l) => sum + l.qty);

  void _inc(int index) => setState(() {
    final line = _lines[index];
    final next = (line.qty + 1).clamp(1, line.maxQty);
    _lines[index] = line.copyWith(qty: next);
  });

  void _dec(int index) => setState(() {
    final line = _lines[index];
    final next = (line.qty - 1).clamp(1, line.maxQty);
    _lines[index] = line.copyWith(qty: next);
  });

  void _remove(int index) => setState(() => _lines.removeAt(index));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final isEmpty = _lines.isEmpty;

    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 380;

    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Review Cart', style: t.titleLarge),
        centerTitle: false,
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
                    itemCount: _lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    itemBuilder: (context, i) {
                      final line = _lines[i];
                      return _CartItemCard(
                        line: line,
                        compact: compact,
                        tokens: tokens,
                        textTheme: t,
                        emojiBase: emojiBase,
                        onMinus: () => _dec(i),
                        onPlus: () => _inc(i),
                        onRemove: () => _remove(i),
                      );
                    },
                  ),
          ),
          _CartBottomBar(
            totalItems: _totalItems,
            enabled: !isEmpty,
            loading: _submitting,
            onConfirm: () async {
              if (_submitting) return;
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
                        // Clear cart after success
                        setState(() => _lines.clear());

                        // Optional: jump to Scan tab if inside AdminShell
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
                      onRetry: () {
                        // just re-trigger confirm
                        // (user taps Try Again, dialog closes, then we start again)
                        Future.microtask(
                          () => _CartPageState()._checkoutRequest(),
                        );
                      },
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

/* ----------------------------- Card Row (Better UX) ----------------------------- */

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.line,
    required this.compact,
    required this.tokens,
    required this.textTheme,
    required this.emojiBase,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
  });

  final _CartLine line;
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
                  color: line.emojiBg,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                ),
                alignment: Alignment.center,
                child: Text(
                  line.emoji,
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
                        line.itemName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: compact ? 16 : 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bucket: ${line.bucketName}',
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
            value: line.qty,
            max: line.maxQty,
            compact: compact,
            onMinus: onMinus,
            onPlus: onPlus,
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- Big Stepper (No tiny numbers) ----------------------------- */

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
            color: enabled ? AppColors.background : AppColors.background,
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

/* ----------------------------- Bottom bar ----------------------------- */

class _CartBottomBar extends StatelessWidget {
  const _CartBottomBar({
    required this.totalItems,
    required this.enabled,
    required this.loading,
    required this.onConfirm,
  });

  final int totalItems;
  final bool enabled;
  final bool loading;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final canPress = enabled && !loading;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          boxShadow: canPress ? tokens.glowShadow : const [],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: FilledButton(
            onPressed: canPress ? onConfirm : null,
            style: FilledButton.styleFrom(foregroundColor: Colors.white),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Confirm Checkout',
                        style: t.labelLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/* ----------------------------- model ----------------------------- */

class _CartLine {
  const _CartLine({
    required this.itemName,
    required this.bucketName,
    required this.qty,
    required this.maxQty,
    required this.emoji,
    required this.emojiBg,
  });

  final String itemName;
  final String bucketName;
  final int qty;
  final int maxQty;
  final String emoji;
  final Color emojiBg;

  _CartLine copyWith({int? qty}) => _CartLine(
    itemName: itemName,
    bucketName: bucketName,
    qty: qty ?? this.qty,
    maxQty: maxQty,
    emoji: emoji,
    emojiBg: emojiBg,
  );
}
