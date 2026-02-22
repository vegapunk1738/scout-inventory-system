import 'package:flutter/material.dart';
import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';

enum CheckoutResultType { success, failure }

class CheckoutResultDialog extends StatelessWidget {
  const CheckoutResultDialog._({
    required this.type,
    required this.title,
    required this.message,
    this.transactionId,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  factory CheckoutResultDialog.success({
    Key? key,
    required String transactionId,
    String title = 'Checkout Complete',
    String message = 'Items successfully checked out.',
    VoidCallback? onFinish,
  }) {
    return CheckoutResultDialog._(
      key: key,
      type: CheckoutResultType.success,
      title: title,
      message: message,
      transactionId: transactionId,
      primaryLabel: 'Finish',
      onPrimary: onFinish,
    );
  }

  factory CheckoutResultDialog.failure({
    Key? key,
    String? errorCode,
    VoidCallback? onRetry,
    VoidCallback? onClose,
  }) {
    return CheckoutResultDialog._(
      key: key,
      type: CheckoutResultType.failure,
      title: 'Checkout Failed',
      message: 'Something went wrong. No items were checked out.',
      transactionId: errorCode,
      primaryLabel: 'Try Again',
      onPrimary: onRetry,
      secondaryLabel: 'Close',
      onSecondary: onClose,
    );
  }

  final CheckoutResultType type;

  final String title;
  final String message;

  final String? transactionId;

  final String primaryLabel;
  final VoidCallback? onPrimary;

  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  bool get _isSuccess => type == CheckoutResultType.success;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final statusColor = _isSuccess ? AppColors.primary : Colors.redAccent;
    final ringBg = statusColor.withValues(alpha: _isSuccess ? 0.10 : 0.12);

    final glow = tokens.glowShadow
        .map((s) => s.copyWith(color: statusColor.withOpacity(s.color.opacity)))
        .toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusXl),
              boxShadow: tokens.cardShadow,
            ),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusIcon(
                  color: statusColor,
                  ringBg: ringBg,
                  icon: _isSuccess ? Icons.check_rounded : Icons.close_rounded,
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                if (transactionId != null) ...[
                  const SizedBox(height: 18),
                  _TxnBox(
                    label: _isSuccess ? 'TRANSACTION ID' : 'ERROR CODE',
                    value: transactionId!,
                  ),
                ],

                const SizedBox(height: 18),

                GlowingFilledButton(
                  height: 62,
                  radius: tokens.radiusLg,
                  label: primaryLabel,
                  icon: Icon(
                    _isSuccess ? Icons.check_rounded : Icons.refresh_rounded,
                  ),
                  backgroundColor: statusColor,
                  foregroundColor: Colors.white,
                  glowShadows: glow,
                  onPressed: () {
                    Navigator.of(context).pop();
                    onPrimary?.call();
                  },
                ),

                if (secondaryLabel != null && onSecondary != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onSecondary?.call();
                      },
                      child: Text(secondaryLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.color,
    required this.ringBg,
    required this.icon,
  });

  final Color color;
  final Color ringBg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(shape: BoxShape.circle, color: ringBg),
          ),

          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
            ),
          ),

          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }
}

class _TxnBox extends StatelessWidget {
  const _TxnBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: t.labelMedium?.copyWith(
              color: AppColors.muted,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: t.headlineSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showCheckoutResultDialog(
  BuildContext context, {
  required Widget child,
  bool barrierDismissible = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Checkout Result',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: child,
        ),
      );
    },
    transitionBuilder: (_, anim, _, w) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: w,
        ),
      );
    },
  );
}
