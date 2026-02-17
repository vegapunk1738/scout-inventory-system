import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Core button: NO SafeArea, NO outer padding.
/// Use this inside dialogs/cards/forms.
class GlowingFilledButton extends StatelessWidget {
  const GlowingFilledButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.height = 62,
    this.radius,
    this.backgroundColor,
    this.foregroundColor,
    this.glowShadows,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  final bool loading;
  final double height;

  /// If null, defaults to tokens.radiusXl
  final double? radius;

  final Color? backgroundColor;
  final Color? foregroundColor;

  /// If null, defaults to tokens.glowShadow when enabled.
  final List<BoxShadow>? glowShadows;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final enabled = onPressed != null && !loading;
    final r = BorderRadius.circular(radius ?? tokens.radiusXl);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: enabled ? (glowShadows ?? tokens.glowShadow) : const [],
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : icon,
          label: Text(loading ? 'Processing…' : label),
          style: FilledButton.styleFrom(
            minimumSize: Size.fromHeight(height),
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            shape: RoundedRectangleBorder(borderRadius: r),
          ),
        ),
      ),
    );
  }
}

/// Bottom-bar wrapper: SafeArea + AnimatedPadding.
/// Use this for Manual Entry / Cart pages.
class GlowingActionButton extends StatelessWidget {
  const GlowingActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.respectKeyboardInset = false,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 34),
    this.height = 74,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  final bool loading;
  final bool respectKeyboardInset;
  final EdgeInsets padding;
  final double height;

  @override
  Widget build(BuildContext context) {
    final kb = respectKeyboardInset
        ? MediaQuery.of(context).viewInsets.bottom
        : 0.0;
    final p = padding.copyWith(bottom: padding.bottom + kb);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: p,
        child: GlowingFilledButton(
          label: label,
          icon: icon,
          onPressed: onPressed,
          loading: loading,
          height: height,
        ),
      ),
    );
  }
}
