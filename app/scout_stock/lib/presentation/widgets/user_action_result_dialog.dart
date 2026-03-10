import 'package:flutter/material.dart';
import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';

enum UserActionResultType { success, failure }

class UserActionResultDialog extends StatelessWidget {
  const UserActionResultDialog._({
    required this.type,
    required this.title,
    required this.message,
    this.detailLabel,
    this.detailValue,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  // ── Success factories ──────────────────────────────────────────────────

  factory UserActionResultDialog.userCreated({
    Key? key,
    required String fullName,
    required String scoutId,
    VoidCallback? onDone,
  }) {
    return UserActionResultDialog._(
      key: key,
      type: UserActionResultType.success,
      title: 'User Created',
      message: '$fullName has been added to the team.',
      detailLabel: 'SCOUT ID',
      detailValue: '#$scoutId',
      primaryLabel: 'Done',
      onPrimary: onDone,
    );
  }

  factory UserActionResultDialog.userUpdated({
    Key? key,
    required String fullName,
    VoidCallback? onDone,
  }) {
    return UserActionResultDialog._(
      key: key,
      type: UserActionResultType.success,
      title: 'User Updated',
      message: '$fullName\'s profile has been saved.',
      primaryLabel: 'Done',
      onPrimary: onDone,
    );
  }

  factory UserActionResultDialog.userDeleted({
    Key? key,
    required String fullName,
    VoidCallback? onDone,
  }) {
    return UserActionResultDialog._(
      key: key,
      type: UserActionResultType.success,
      title: 'User Deleted',
      message: '$fullName has been removed from the team.',
      primaryLabel: 'Done',
      onPrimary: onDone,
    );
  }

  // ── Failure factory ────────────────────────────────────────────────────

  factory UserActionResultDialog.failure({
    Key? key,
    required String errorMessage,
    String title = 'Action Failed',
    String? errorCode,
    VoidCallback? onRetry,
    VoidCallback? onClose,
  }) {
    return UserActionResultDialog._(
      key: key,
      type: UserActionResultType.failure,
      title: title,
      message: errorMessage,
      detailLabel: errorCode != null ? 'ERROR CODE' : null,
      detailValue: errorCode,
      primaryLabel: 'Try Again',
      onPrimary: onRetry,
      secondaryLabel: 'Close',
      onSecondary: onClose,
    );
  }

  final UserActionResultType type;

  final String title;
  final String message;

  final String? detailLabel;
  final String? detailValue;

  final String primaryLabel;
  final VoidCallback? onPrimary;

  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  bool get _isSuccess => type == UserActionResultType.success;

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
                  icon: _isSuccess
                      ? Icons.check_rounded
                      : Icons.close_rounded,
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

                if (detailLabel != null && detailValue != null) ...[
                  const SizedBox(height: 18),
                  _DetailBox(label: detailLabel!, value: detailValue!),
                ],

                const SizedBox(height: 18),

                GlowingFilledButton(
                  height: 62,
                  radius: tokens.radiusLg,
                  label: primaryLabel,
                  icon: Icon(
                    _isSuccess
                        ? Icons.check_rounded
                        : Icons.refresh_rounded,
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

// ═══════════════════════════════════════════════════════════════════════════
// Private widgets — same look as CheckoutResultDialog
// ═══════════════════════════════════════════════════════════════════════════

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

class _DetailBox extends StatelessWidget {
  const _DetailBox({required this.label, required this.value});

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

/// Shows the dialog with the same transition as [showCheckoutResultDialog].
Future<void> showUserActionResultDialog(
  BuildContext context, {
  required Widget child,
  bool barrierDismissible = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'User Action Result',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: child,
        ),
      );
    },
    transitionBuilder: (_, anim, __, w) {
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