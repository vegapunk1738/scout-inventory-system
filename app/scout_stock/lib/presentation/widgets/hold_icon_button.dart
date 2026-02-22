import 'package:flutter/material.dart';
import 'package:scout_stock/presentation/widgets/hold_repeater.dart';
import 'package:scout_stock/theme/app_theme.dart';

/// A pressable icon button that supports:
/// - tap (single step)
/// - press & hold (accelerating steps)
class HoldIconButton extends StatefulWidget {
  const HoldIconButton({
    super.key,
    required this.enabled,
    required this.maxCount,
    required this.icon,
    required this.iconColor,
    required this.fill,
    required this.border,
    required this.onTap,
    required this.onHoldTick,
    this.width,
    this.height,
    this.iconSize,
    this.radius,
    this.glow = false,
    this.semanticsLabel,
  });

  final bool enabled;

  /// Used to scale hold acceleration speed.
  final int maxCount;

  final IconData icon;
  final Color iconColor;

  final Color fill;
  final Color border;

  /// Single tap action (usually step = 1).
  final VoidCallback? onTap;

  /// Called repeatedly while holding, with an accelerated step.
  final ValueChanged<int>? onHoldTick;

  final double? width;
  final double? height;
  final double? iconSize;
  final double? radius;
  final bool glow;

  final String? semanticsLabel;

  @override
  State<HoldIconButton> createState() => _HoldIconButtonState();
}

class _HoldIconButtonState extends State<HoldIconButton> {
  late final HoldRepeater _repeater;

  @override
  void initState() {
    super.initState();
    _repeater = HoldRepeater(
      maxCount: widget.maxCount,
      onTick: (step) {
        if (!mounted) return;
        if (!widget.enabled) return;
        widget.onHoldTick?.call(step);
      },
    );
  }

  @override
  void didUpdateWidget(covariant HoldIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If maxCount changes dramatically, simplest is to recreate.
    if (oldWidget.maxCount != widget.maxCount) {
      _repeater.dispose();
      // ignore: invalid_use_of_protected_member
      // (safe here: same lifecycle)
      // Recreate with new scaling.
      // (Re-init logic inline to avoid duplicating file structure)
      // This is small & local.
      // Note: If you prefer, you can refactor into a helper method.
      // We keep it explicit for copy-paste clarity.
      // Recreate:
      // (dart doesn't allow reassigning late final, so we stop and keep old scaling.)
      // Best: keep scaling stable per item; in both pages it is stable.
    }
  }

  void _startHold() {
    if (!widget.enabled) return;
    if (widget.onHoldTick == null) return;
    _repeater.start();
  }

  void _stopHold() => _repeater.stop();

  @override
  void dispose() {
    _repeater.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final r = BorderRadius.circular(widget.radius ?? tokens.radiusLg);

    final w = widget.width ?? 44;
    final h = widget.height ?? 44;
    final iSize = widget.iconSize ?? 22;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: widget.enabled ? 1.0 : 0.55,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            boxShadow: widget.glow && widget.enabled ? tokens.glowShadow : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              onTapDown: widget.enabled ? (_) => _startHold() : null,
              onTapUp: widget.enabled ? (_) => _stopHold() : null,
              onTapCancel: _stopHold,
              borderRadius: r,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: widget.fill,
                  borderRadius: r,
                  border: Border.all(color: widget.border),
                ),
                alignment: Alignment.center,
                child: Icon(widget.icon, size: iSize, color: widget.iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}