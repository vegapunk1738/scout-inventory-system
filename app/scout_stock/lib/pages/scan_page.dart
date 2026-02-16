import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';
import 'manual_entry_page.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  StreamSubscription<BarcodeCapture>? _sub;

  String? _lastRaw;
  DateTime? _lastAt;
  String? _lastBucketLabel;

  final int _cartCount = 3;
  _BottomTab _tab = _BottomTab.scan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = MobileScannerController(
      autoStart: true,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [BarcodeFormat.code128],
      // Torch is not usable on Flutter Web; don’t surface it in UI.
      torchEnabled: false,
    );

    _sub = _controller.barcodes.listen(_handleBarcodeCapture);
    unawaited(_controller.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts can cause lifecycle changes before the controller is ready.
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _sub ??= _controller.barcodes.listen(_handleBarcodeCapture);
        unawaited(_controller.start());
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_sub?.cancel());
        _sub = null;
        unawaited(_controller.stop());
        break;
    }
  }

  void _handleBarcodeCapture(BarcodeCapture capture) {
    if (!mounted) return;
    if (capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    // Extra debounce for “fast and forgiving”.
    final now = DateTime.now();
    if (_lastRaw == raw &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 2)) {
      return;
    }

    _lastRaw = raw;
    _lastAt = now;

    final label = _bucketLabelFromRaw(raw);
    setState(() => _lastBucketLabel = label);

    // TODO: Replace with your real navigation:
    // context.go('/bucket/$bucketId');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scanned $label'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  String _bucketLabelFromRaw(String raw) {
    // Accepts "921", "Bucket-921", "BKT:921", etc.
    debugPrint('$raw');
    final m = RegExp(r'(\d+)').firstMatch(raw);
    if (m != null) return 'Bucket #${m.group(1)}';
    return raw;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel());
    _sub = null;
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final safe = MediaQuery.paddingOf(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;

          // --- Layout constants (tuned to avoid overflow) ---
          const sidePad = 16.0;
          const topPad = 10.0;

          const topRowH = 56.0;
          const titleBlockH = 52.0; // title + small spacing
          const autoPillH = 40.0;

          const manualBtnH = 68.0;
          const bottomNavH = 78.0;

          const gapAfterTopRow = 14.0;
          const gapTitleToFrame = 14.0;
          const gapFrameToPill = 12.0;
          const gapPillToBottom = 12.0;
          const gapManualToNav = 14.0;
          const bottomPad = 10.0;

          final usableH = h - safe.top - safe.bottom;

          // Bottom area height
          final bottomAreaH =
              manualBtnH + gapManualToNav + bottomNavH + bottomPad;

          // How much height can the scan frame take?
          final reservedH =
              topPad +
              topRowH +
              gapAfterTopRow +
              titleBlockH +
              gapTitleToFrame +
              autoPillH +
              gapFrameToPill +
              gapPillToBottom +
              bottomAreaH;

          final maxFrameByH = (usableH - reservedH);
          final maxFrameByW = (w - sidePad * 2);

          // Allow it to shrink pretty small on short devices (prevents overflow).
          final frameSize = math
              .min(maxFrameByW, maxFrameByH)
              .clamp(110.0, 420.0)
              .toDouble();

          // Y positions
          final topY = safe.top + topPad;
          final titleY = topY + topRowH + gapAfterTopRow;
          final frameY = titleY + titleBlockH + gapTitleToFrame;

          final navBottom = safe.bottom + bottomPad;
          final navTop = h - navBottom - bottomNavH;

          final manualBottom = navTop - gapManualToNav;
          final manualTop = manualBottom - manualBtnH;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera
              MobileScanner(controller: _controller, fit: BoxFit.cover),

              // Soft blur + dark gradient for readability
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.24, 0.62, 1.0],
                        colors: [
                          Colors.black.withOpacity(0.40),
                          Colors.black.withOpacity(0.10),
                          Colors.black.withOpacity(0.18),
                          Colors.black.withOpacity(0.55),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Top row: last scanned (shrink-wrapped)
              Positioned(
                top: topY,
                left: sidePad,
                right: sidePad,
                height: topRowH,
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        // prevents it from becoming huge on wide screens
                        maxWidth: math.min(320.0, w - sidePad * 2),
                      ),
                      child: _LastScannedPill(
                        label: _lastBucketLabel ?? '—',
                        enabled: _lastBucketLabel != null,
                        onTap: _lastBucketLabel == null
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Open ${_lastBucketLabel!}'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(milliseconds: 800),
                                  ),
                                );
                              },
                      ),
                    ),
                    const Spacer(),
                    // If you ever add a right-side button later, it goes here.
                  ],
                ),
              ),

              // Title
              Positioned(
                top: titleY + 20,
                left: sidePad,
                right: sidePad,
                child: Column(
                  children: [
                    Text(
                      'Align barcode within frame',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withOpacity(0.92),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),

              // Scan frame
              Positioned(
                top: frameY,
                left: (w - frameSize) / 2,
                width: frameSize,
                height: frameSize,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(color: Colors.black.withOpacity(0.08)),
                      ),
                      CustomPaint(
                        painter: _ScanFramePainter(
                          cornerColor: AppColors.primary,
                          borderColor: Colors.white.withOpacity(0.42),
                        ),
                        child: const SizedBox.expand(),
                      ),
                      Center(
                        child: Icon(
                          Icons.add,
                          size: 34,
                          color: Colors.white.withOpacity(0.40),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Auto scan pill (purely UI)
              Positioned(
                top: frameY + frameSize + gapFrameToPill,
                left: 0,
                right: 0,
                child: Center(
                  child: _AutoScanPill(
                    text: 'AUTO-SCAN ENABLED',
                    icon: Icons.qr_code_scanner,
                    tokens: tokens,
                  ),
                ),
              ),

              // Manual entry button
              Positioned(
                top: manualTop,
                left: sidePad,
                right: sidePad,
                height: manualBtnH,
                child: _ManualEntryButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ManualEntryPage(),
                      ),
                    );
                  },
                ),
              ),

              // Bottom nav
              Positioned(
                top: navTop,
                left: 12,
                right: 12,
                height: bottomNavH,
                child: _BottomNavBar(
                  selected: _tab,
                  cartCount: _cartCount,
                  onSelect: (t) => setState(() => _tab = t),
                ),
              ),

              // Permission helper overlay (optional but nice on web)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _controller,
                    builder: (_, state, __) {
                      if (state.hasCameraPermission) return const SizedBox();
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                          child: Text(
                            'Camera permission needed to scan.\nCheck your browser site settings.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white.withOpacity(0.92),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _BottomTab { scan, cart, me }

class _LastScannedPill extends StatelessWidget {
  const _LastScannedPill({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.primary.withOpacity(0.22);
    final fg = Colors.white.withOpacity(0.92);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min, // <-- key
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history, color: fg, size: 18),
            ),
            const SizedBox(width: 10),

            // Was Expanded(...) -> change to Flexible(loose)
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LAST SCANNED',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: fg.withOpacity(0.75),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFF19C37D)
                    : Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                size: 14,
                color: enabled ? Colors.white : Colors.white.withOpacity(0.50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoScanPill extends StatelessWidget {
  const _AutoScanPill({
    required this.text,
    required this.icon,
    required this.tokens,
  });

  final String text;
  final IconData icon;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white.withOpacity(0.85)),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withOpacity(0.85),
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualEntryButton extends StatelessWidget {
  const _ManualEntryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      decoration: BoxDecoration(
        boxShadow: tokens.cardShadow,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(68),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusXl),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.keyboard_rounded, size: 22),
            const SizedBox(width: 12),
            Text(
              'Enter Code Manually',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.selected,
    required this.cartCount,
    required this.onSelect,
  });

  final _BottomTab selected;
  final int cartCount;
  final ValueChanged<_BottomTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final selectedColor = AppColors.primary;
    final unselectedColor = Colors.white.withOpacity(0.65);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 78,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(tokens.radiusXl),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  _NavItem(
                    label: 'Scan',
                    icon: Icons.qr_code_scanner_rounded,
                    selected: selected == _BottomTab.scan,
                    selectedColor: selectedColor,
                    unselectedColor: unselectedColor,
                    onTap: () => onSelect(_BottomTab.scan),
                  ),
                  const Spacer(),
                  const SizedBox(width: 84),
                  const Spacer(),
                  _NavItem(
                    label: 'Me',
                    icon: Icons.person_rounded,
                    selected: selected == _BottomTab.me,
                    selectedColor: selectedColor,
                    unselectedColor: unselectedColor,
                    onTap: () => onSelect(_BottomTab.me),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 10,
          child: GestureDetector(
            onTap: () => onSelect(_BottomTab.cart),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: tokens.glowShadow,
                  ),
                  child: const Icon(
                    Icons.shopping_cart_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                if (cartCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE5484D),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$cartCount',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color, letterSpacing: 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({required this.cornerColor, required this.borderColor});

  final Color cornerColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(r, borderPaint);

    final cornerPaint = Paint()
      ..color = cornerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const cornerLen = 34.0;
    const inset = 2.0;

    // TL
    canvas.drawLine(
      Offset(inset, cornerLen),
      const Offset(inset, inset),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(inset, inset),
      Offset(cornerLen, inset),
      cornerPaint,
    );

    // TR
    canvas.drawLine(
      Offset(size.width - cornerLen, inset),
      Offset(size.width - inset, inset),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(size.width - inset, cornerLen),
      cornerPaint,
    );

    // BL
    canvas.drawLine(
      Offset(inset, size.height - cornerLen),
      Offset(inset, size.height - inset),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(cornerLen, size.height - inset),
      cornerPaint,
    );

    // BR
    canvas.drawLine(
      Offset(size.width - cornerLen, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - cornerLen),
      Offset(size.width - inset, size.height - inset),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) {
    return oldDelegate.cornerColor != cornerColor ||
        oldDelegate.borderColor != borderColor;
  }
}
