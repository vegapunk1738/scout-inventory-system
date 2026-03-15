import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scout_stock/domain/models/item.dart';
import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';

enum CheckoutResultType { success, failure }

/// Compact checkout result shown as a dialog.
///
/// **Success** — shows the items that were checked out with emoji, name,
/// quantity, and which bucket they came from.
///
/// **Failure** — shows the backend error message so the user knows exactly
/// what went wrong (race condition, deleted item, etc.).
class CheckoutResultDialog extends StatelessWidget {
  const CheckoutResultDialog._({
    required this.type,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.items = const [],
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  factory CheckoutResultDialog.success({
    Key? key,
    required List<Item> items,
    String title = 'Checked out!',
    VoidCallback? onFinish,
  }) {
    final totalQty = items.fold<int>(0, (s, it) => s + it.quantity);
    final itemTypes = items.length;
    final message =
        '$totalQty item${totalQty == 1 ? '' : 's'} '
        'from $itemTypes type${itemTypes == 1 ? '' : 's'}';

    return CheckoutResultDialog._(
      key: key,
      type: CheckoutResultType.success,
      title: title,
      message: message,
      items: items,
      primaryLabel: 'Done',
      onPrimary: onFinish,
    );
  }

  factory CheckoutResultDialog.failure({
    Key? key,
    String? errorMessage,
    VoidCallback? onRetry,
    VoidCallback? onClose,
  }) {
    return CheckoutResultDialog._(
      key: key,
      type: CheckoutResultType.failure,
      title: 'Checkout failed',
      message:
          errorMessage ?? 'Something went wrong. No items were checked out.',
      primaryLabel: 'Close',
      onPrimary: onRetry,
      secondaryLabel: 'Close',
      onSecondary: onClose,
    );
  }

  /// Compact success dialog for returns (no item list, just a message).
  factory CheckoutResultDialog.returnSuccess({
    Key? key,
    required int itemCount,
    String title = 'Returned!',
    VoidCallback? onFinish,
  }) {
    return CheckoutResultDialog._(
      key: key,
      type: CheckoutResultType.success,
      title: title,
      message: '$itemCount item${itemCount == 1 ? '' : 's'} returned',
      primaryLabel: 'Done',
      onPrimary: onFinish,
    );
  }

  final CheckoutResultType type;
  final String title;
  final String message;
  final List<Item> items;
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
        constraints: const BoxConstraints(maxWidth: 380),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusXl),
              boxShadow: tokens.cardShadow,
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Status icon (compact) ──
                _StatusIcon(
                  color: statusColor,
                  ringBg: ringBg,
                  icon: _isSuccess ? Icons.check_rounded : Icons.close_rounded,
                ),
                const SizedBox(height: 10),

                // ── Title ──
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: t.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),

                // ── Subtitle ──
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                // ── Item summary (success only) ──
                if (_isSuccess && items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ItemSummaryBox(items: items, tokens: tokens),
                ],

                const SizedBox(height: 16),

                // ── Primary button ──
                GlowingFilledButton(
                  height: 54,
                  radius: tokens.radiusLg,
                  label: primaryLabel,
                  icon: Icon(
                    _isSuccess ? Icons.check_rounded : Icons.close,
                    size: 20,
                  ),
                  backgroundColor: statusColor,
                  foregroundColor: Colors.white,
                  glowShadows: glow,
                  onPressed: () {
                    Navigator.of(context).pop();
                    onPrimary?.call();
                  },
                ),

                // ── Secondary button (failure only) ──
                if (secondaryLabel != null && onSecondary != null) ...[
                  const SizedBox(height: 8),
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
// Private widgets
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
      width: 68,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(shape: BoxShape.circle, color: ringBg),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}

/// Shows a compact scrollable list of checked-out items inside a bordered box.
class _ItemSummaryBox extends StatelessWidget {
  const _ItemSummaryBox({required this.items, required this.tokens});

  final List<Item> items;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);

    // Group items by bucket for a cleaner presentation
    final bucketGroups = <String, List<Item>>{};
    for (final item in items) {
      (bucketGroups[item.bucketBarcode] ??= []).add(item);
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 0.5,
          color: AppColors.outline.withValues(alpha: 0.6),
        ),
        itemBuilder: (context, i) {
          final item = items[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                // Emoji
                Text(item.emoji, style: emojiBase.copyWith(fontSize: 18)),
                const SizedBox(width: 10),

                // Name + bucket
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        item.bucketBarcode,
                        style: t.bodySmall?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Quantity pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '×${item.quantity}',
                    style: t.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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
