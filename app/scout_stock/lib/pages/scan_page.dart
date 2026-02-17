// scan_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';
import '../widgets/admin_shell.dart';
import 'manual_entry_page.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  static const int _scanTabIndex = 0;

  late final MobileScannerController _controller;
  StreamSubscription<BarcodeCapture>? _sub;

  ValueNotifier<int>? _navIndex;
  bool _isActive = false;

  // Serialize camera ops to avoid flaky web timing issues.
  Future<void> _cameraQueue = Future.value();

  // Strong guards (don’t rely on controller.value.isRunning on web)
  bool _starting = false;
  bool _stopping = false;
  bool _running = false;

  String? _lastRaw;
  DateTime? _lastAt;
  String? _lastBucketLabel;

  static final RegExp _digits = RegExp(r'(\d+)');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [BarcodeFormat.code128],
      torchEnabled: false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final next = AdminShellScope.maybeOf(context);
    if (!identical(_navIndex, next)) {
      _navIndex?.removeListener(_onNavIndexChanged);
      _navIndex = next;
      _navIndex?.addListener(_onNavIndexChanged);
    }

    _onNavIndexChanged();
  }

  void _onNavIndexChanged() {
    final shouldBeActive = _navIndex == null
        ? true
        : _navIndex!.value == _scanTabIndex;
    if (shouldBeActive == _isActive) return;

    _isActive = shouldBeActive;

    if (_isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isActive) _enqueueCamera(_activateScanner);
      });
    } else {
      _enqueueCamera(_deactivateScanner);
    }

    setState(() {});
  }

  void _enqueueCamera(Future<void> Function() task) {
    _cameraQueue = _cameraQueue.then((_) => task()).catchError((_) {});
  }

  Future<void> _activateScanner() async {
    if (!mounted || !_isActive) return;
    if (_running || _starting) return;

    _starting = true;
    try {
      // Attach listener while active
      _sub ??= _controller.barcodes.listen(_handleBarcodeCapture);

      // If a stop is in progress, let it finish
      if (_stopping) return;

      await _controller.start();
      _running = true;
    } catch (e) {
      // If start fails, allow future retries
      debugPrint('ScanPage: start failed: $e');
      _running = false;
    } finally {
      _starting = false;
    }
  }

  Future<void> _deactivateScanner() async {
    if (_stopping) return;

    _stopping = true;
    try {
      // Stop receiving events first (reduces work while hidden)
      try {
        await _sub?.cancel();
      } catch (_) {}
      _sub = null;

      if (_running || _starting) {
        try {
          await _controller.stop();
        } catch (_) {}
      }
      _running = false;
    } finally {
      _stopping = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isActive) return;

    switch (state) {
      case AppLifecycleState.resumed:
        // resume can fire around the same time as tab change -> queue it
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isActive) _enqueueCamera(_activateScanner);
        });
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _enqueueCamera(_deactivateScanner);
        break;
    }
  }

  void _handleBarcodeCapture(BarcodeCapture capture) {
    if (!mounted || !_isActive) return;
    if (capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final now = DateTime.now();
    if (_lastRaw == raw &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 2)) {
      return;
    }

    _lastRaw = raw;
    _lastAt = now;

    final label = _bucketLabelFromRaw(raw);
    if (label != _lastBucketLabel) {
      setState(() => _lastBucketLabel = label);
    }
  }

  String _bucketLabelFromRaw(String raw) {
    final m = _digits.firstMatch(raw);
    if (m != null) return 'Bucket #${m.group(1)}';
    return raw;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navIndex?.removeListener(_onNavIndexChanged);
    _navIndex = null;

    // Best-effort shutdown
    unawaited(_deactivateScanner());
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final safe = MediaQuery.paddingOf(context);

    // BackdropFilter is expensive on Web. Keep look on mobile, skip blur on web.
    final allowBlur = !kIsWeb;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;

          // --- Layout constants ---
          const sidePad = 16.0;
          const topPad = 10.0;

          const topRowH = 56.0;
          const titleBlockH = 52.0;
          const autoPillH = 40.0;

          const manualBtnH = 68.0;

          const gapAfterTopRow = 14.0;
          const gapTitleToFrame = 14.0;
          const gapFrameToPill = 12.0;
          const gapPillToBottom = 12.0;

          const shellNavHeight = 78.0;
          const shellNavBottomPad = 12.0;

          const manualBottomInset = 100.0;

          final usableH = h - safe.top - safe.bottom;
          final bottomAreaH = manualBtnH + shellNavHeight + shellNavBottomPad;

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

          final frameSize = math
              .min(maxFrameByW, maxFrameByH)
              .clamp(110.0, 420.0)
              .toDouble();

          final topY = safe.top + topPad;
          final titleY = topY + topRowH + gapAfterTopRow;
          final frameY = titleY + titleBlockH + gapTitleToFrame;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera ONLY when Scan tab is active
              if (_isActive)
                RepaintBoundary(
                  child: MobileScanner(
                    controller: _controller,
                    fit: BoxFit.cover,
                  ),
                )
              else
                const ColoredBox(color: Colors.black),

              // Gradient overlay (no full-screen blur)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.24, 0.62, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0.40),
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),

              // Top pill
              Positioned(
                top: topY,
                left: sidePad,
                right: sidePad,
                height: topRowH,
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.min(320.0, w - sidePad * 2),
                      ),
                      child: _LastScannedPill(
                        label: _lastBucketLabel ?? '—',
                        enabled: _lastBucketLabel != null,
                        onTap: _lastBucketLabel == null
                            ? null
                            : () => debugPrint(
                                'Open Last Scanned $_lastBucketLabel',
                              ),
                      ),
                    ),
                    const Spacer(),
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
                        color: Colors.white.withValues(alpha: 0.92),
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
                      if (allowBlur)
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        )
                      else
                        Container(color: Colors.black.withValues(alpha: 0.14)),
                      CustomPaint(
                        painter: _ScanFramePainter(
                          cornerColor: AppColors.primary,
                          borderColor: Colors.white.withValues(alpha: 0.42),
                        ),
                        child: const SizedBox.expand(),
                      ),
                      Center(
                        child: Icon(
                          Icons.add,
                          size: 34,
                          color: Colors.white.withValues(alpha: 0.40),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Auto scan pill
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
                left: sidePad,
                right: sidePad,
                bottom: manualBottomInset,
                height: manualBtnH,
                child: _ManualEntryButton(
                  allowBlur: allowBlur,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ManualEntryPage(),
                      ),
                    );
                  },
                ),
              ),

              // Permission helper overlay (only when active)
              if (_isActive)
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
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              'Camera permission needed to scan.\nCheck your browser site settings.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.92),
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

/* ----------------------------- UI PARTS ----------------------------- */

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
    final bg = AppColors.primary.withValues(alpha: 0.22);
    final fg = Colors.white.withValues(alpha: 0.92);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history, color: fg, size: 18),
            ),
            const SizedBox(width: 10),
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
                      color: fg.withValues(alpha: 0.75),
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
                    : Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                size: 14,
                color: enabled
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.50),
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
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualEntryButton extends StatelessWidget {
  const _ManualEntryButton({required this.onPressed, required this.allowBlur});

  final VoidCallback onPressed;
  final bool allowBlur;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        splashColor: Colors.white.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.06),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(tokens.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.keyboard_rounded,
                size: 22,
                color: Colors.white.withValues(alpha: 0.92),
              ),
              const SizedBox(width: 12),
              Text(
                'Enter Code Manually',
                style: t.titleLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radiusXl),
      child: allowBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: content,
            )
          : content,
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
