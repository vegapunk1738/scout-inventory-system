import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/state/providers/cart_provider.dart';

import '../../domain/models/item.dart';
import '../../theme/app_theme.dart';
import '../widgets/glowing_action_button.dart';

class BucketItemPage extends ConsumerStatefulWidget {
  const BucketItemPage({super.key, required this.barcode});
  final String barcode;

  @override
  ConsumerState<BucketItemPage> createState() => _BucketItemPageState();
}

class _BucketItemPageState extends ConsumerState<BucketItemPage> {
  // Mocked (for ABC-ABC-123)
  final int bucketNumber = 42;
  final String bucketName = 'Patrol Box Alpha';

  final String itemName = 'Propane Canisters';
  // keep SKU removed from UI (this variable is harmless)
  final String sku = 'OUT-PRO-16OZ';

  final int maxCount = 1000; // “max”
  int qty = 12;

  bool _loading = false;

  late final _HoldRepeater _incHold;
  late final _HoldRepeater _decHold;

  @override
  void initState() {
    super.initState();

    _incHold = _HoldRepeater(
      maxCount: maxCount,
      onTick: (step) => _applyDelta(step),
    );
    _decHold = _HoldRepeater(
      maxCount: maxCount,
      onTick: (step) => _applyDelta(-step),
    );
  }

  @override
  void dispose() {
    _incHold.dispose();
    _decHold.dispose();
    super.dispose();
  }

  void _applyDelta(int delta) {
    if (!mounted) return;

    final next = (qty + delta).clamp(0, maxCount);
    if (next == qty) return;

    HapticFeedback.selectionClick();
    setState(() => qty = next);
  }

  void _decTap() => _applyDelta(-1);
  void _incTap() => _applyDelta(1);

  // ✅ ADD TO CART now writes to CartNotifier then pops back to ScanPage
  Future<void> _addToCart() async {
    if (_loading || qty <= 0) return;
    setState(() => _loading = true);

    // Build an Item (mock IDs for now — replace later when real data is wired)
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

    // Add/merge into cart
    ref.read(cartProvider.notifier).addItem(item);

    // Optional tiny delay so the loading state is visible (feels responsive)
    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!mounted) return;
    setState(() => _loading = false);

    // Go back to scanner (ScanPage will resume camera in your existing .then handler)
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
          const Positioned.fill(child: _DottedBackground()),
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
                  _HoldIconButton(
                    enabled: canDec,
                    fill: const Color(0xFFF8FAFC),
                    border: AppColors.outline,
                    icon: Icons.remove,
                    iconColor: canDec
                        ? AppColors.ink.withValues(alpha: 0.70)
                        : AppColors.ink.withValues(alpha: 0.25),
                    onTap: canDec ? _decTap : null,
                    onHoldStart: canDec ? _decHold.start : null,
                    onHoldEnd: _decHold.stop,
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
                  _HoldIconButton(
                    enabled: canInc,
                    fill: AppColors.primary,
                    border: Colors.transparent,
                    glow: true,
                    icon: Icons.add,
                    iconColor: Colors.white,
                    onTap: canInc ? _incTap : null,
                    onHoldStart: canInc ? _incHold.start : null,
                    onHoldEnd: _incHold.stop,
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

/* ------------------------- Hold-to-accelerate ------------------------- */

class _HoldRepeater {
  _HoldRepeater({required int maxCount, required this.onTick})
    : _maxCount = math.max(1, maxCount),
      _tickEvery = _calcTickEvery(math.max(1, maxCount)),
      _doubleEveryTicks = _calcDoubleEveryTicks(math.max(1, maxCount)),
      _capStep = _calcCapStep(math.max(1, maxCount)),
      _holdDelay = _calcHoldDelay(math.max(1, maxCount));

  final void Function(int step) onTick;

  final int _maxCount;
  final Duration _tickEvery;
  final Duration _holdDelay;
  final int _doubleEveryTicks;
  final int _capStep;

  Timer? _delayTimer;
  Timer? _repeatTimer;

  int _ticks = 0;
  int _step = 1;

  static double _log10(int x) => math.log(x.toDouble()) / math.ln10;

  static Duration _calcTickEvery(int max) {
    final m = _log10(max).clamp(1.0, 4.0);
    final ms = (80 - (m * 10)).round().clamp(45, 80);
    return Duration(milliseconds: ms);
  }

  static Duration _calcHoldDelay(int max) {
    final m = _log10(max).clamp(1.0, 4.0);
    final ms = (240 - (m * 20)).round().clamp(150, 240);
    return Duration(milliseconds: ms);
  }

  static int _calcDoubleEveryTicks(int max) {
    final m = _log10(max).clamp(1.0, 4.0);
    final v = (8 - (m * 2)).round().clamp(2, 8);
    return v;
  }

  static int _calcCapStep(int max) {
    return ((max / 4).ceil()).clamp(1, 2000);
  }

  void start() {
    stop();

    _delayTimer = Timer(_holdDelay, () {
      _ticks = 0;
      _step = 1;

      _repeatTimer = Timer.periodic(_tickEvery, (_) {
        _ticks++;

        if (_ticks % _doubleEveryTicks == 0) {
          _step = math.min(_step * 2, _capStep);
        }

        onTick(_step);
      });
    });
  }

  void stop() {
    _delayTimer?.cancel();
    _delayTimer = null;

    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void dispose() => stop();
}

/* ------------------------------ UI Bits ------------------------------ */

class _HoldIconButton extends StatelessWidget {
  const _HoldIconButton({
    required this.enabled,
    required this.fill,
    required this.border,
    required this.icon,
    required this.iconColor,
    required this.onHoldEnd,
    this.onTap,
    this.onHoldStart,
    this.glow = false,
  });

  final bool enabled;
  final Color fill;
  final Color border;
  final IconData icon;
  final Color iconColor;
  final bool glow;

  final VoidCallback? onTap;
  final VoidCallback? onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: enabled ? 1.0 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          boxShadow: glow && enabled ? tokens.glowShadow : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            onTapDown: enabled ? (_) => onHoldStart?.call() : null,
            onTapUp: enabled ? (_) => onHoldEnd() : null,
            onTapCancel: onHoldEnd,
            borderRadius: BorderRadius.circular(tokens.radiusXl),
            child: Container(
              width: 64,
              height: 62,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(tokens.radiusXl),
                border: Border.all(color: border),
              ),
              child: Center(child: Icon(icon, size: 30, color: iconColor)),
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedBackground extends StatelessWidget {
  const _DottedBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotsPainter(
        dotColor: AppColors.ink.withValues(alpha: 0.05),
        spacing: 18,
        radius: 1.2,
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.dotColor,
    required this.spacing,
    required this.radius,
  });

  final Color dotColor;
  final double spacing;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.spacing != spacing ||
        oldDelegate.radius != radius;
  }
}
