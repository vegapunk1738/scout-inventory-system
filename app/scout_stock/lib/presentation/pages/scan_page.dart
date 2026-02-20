// scan_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:scout_stock/presentation/pages/bucket_single_item_page.dart';

import '../../theme/app_theme.dart';
import '../widgets/admin_shell.dart';
import 'manual_entry_page.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const int _scanTabIndex = 0;

  late final MobileScannerController _controller;
  StreamSubscription<BarcodeCapture>? _sub;

  ValueNotifier<int>? _navIndex;
  bool _isActive = false;

  // Serialize camera ops to avoid flaky web timing issues.
  Future<void> _cameraQueue = Future.value();

  // Strong guards (don’t rely on controller.value.isRunning on web only)
  bool _starting = false;
  bool _stopping = false;
  bool _running = false;

  // Camera readiness + snap fade
  bool _feedReady = false;
  bool _uiReady = false;
  bool _fading = false;

  late final AnimationController _blackFade; // 1.0 = black, 0.0 = clear
  VoidCallback? _controllerListener;

  String? _lastRaw;
  DateTime? _lastAt;
  String? _lastBucketLabel;

  static final RegExp _digits = RegExp(r'(\d+)');

  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _blackFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1.0, // start fully black
    );

    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [BarcodeFormat.code128],
      torchEnabled: false,
    );

    _controllerListener = () {
      if (!mounted) return;
      final s = _controller.value;

      final readyNow = s.hasCameraPermission && s.isRunning;

      // When the feed becomes ready, fade from black -> video and then show UI.
      if (_isActive && readyNow && !_feedReady) {
        _feedReady = true;
        _startSnapFade();
      }
    };
    _controller.addListener(_controllerListener!);
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
      _resetFadeState();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isActive) _enqueueCamera(_activateScanner);
      });
    } else {
      _enqueueCamera(_deactivateScanner);
      if (mounted) {
        setState(() {
          _feedReady = false;
          _uiReady = false;
        });
      }
      _blackFade.value = 1.0;
    }

    setState(() {});
  }

  void _enqueueCamera(Future<void> Function() task) {
    _cameraQueue = _cameraQueue.then((_) => task()).catchError((_) {});
  }

  void _resetFadeState() {
    _feedReady = false;
    _uiReady = false;
    _fading = false;
    _blackFade.value = 1.0; // black cover up immediately
    if (mounted) setState(() {});
  }

  Future<void> _startSnapFade() async {
    if (!mounted) return;
    if (_fading) return;

    _fading = true;

    // Keep UI hidden until the fade finishes (Snapchat-y)
    if (mounted) setState(() => _uiReady = false);

    try {
      await _blackFade.animateTo(0.0, curve: Curves.easeOutCubic);
    } catch (_) {
      // ignore animation cancellations
    } finally {
      _fading = false;
      if (mounted && _isActive && _feedReady) {
        setState(() => _uiReady = true);
      }
    }
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

      // Give UI a frame to paint the black cover before camera start
      await Future<void>.delayed(const Duration(milliseconds: 16));

      await _controller.start();
      _running = true;

      // Fallback: if listener is late, poll briefly then trigger fade.
      final ready = await _waitUntilVideoRunning(
        timeout: const Duration(seconds: 2),
      );
      if (mounted && _isActive && ready && !_feedReady) {
        _feedReady = true;
        _startSnapFade();
      }
    } catch (e) {
      debugPrint('ScanPage: start failed: $e');
      _running = false;
      if (mounted) {
        // If start fails, remove black so user isn't stuck (permission overlay still shows).
        _blackFade.value = 0.0;
        setState(() {
          _feedReady = false;
          _uiReady = true; // allow UI so user can still tap manual entry, etc.
        });
      }
    } finally {
      _starting = false;
    }
  }

  Future<bool> _waitUntilVideoRunning({required Duration timeout}) async {
    final start = DateTime.now();
    while (mounted && _isActive) {
      final s = _controller.value;
      if (s.hasCameraPermission && s.isRunning) return true;
      if (DateTime.now().difference(start) > timeout) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
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

    // ✅ Navigate to bucket page when this code is scanned
    if (raw == 'ABC-ABC-123' && !_navigating) {
      _navigating = true;

      // Stop camera while inside the bucket page (privacy + performance)
      _enqueueCamera(_deactivateScanner);

      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => BucketItemPage(barcode: raw)))
          .then((_) {
            if (!mounted) return;
            _navigating = false;

            // Resume scanning when returning
            if (_isActive) {
              _resetFadeState();
              _enqueueCamera(_activateScanner);
            }
          });
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

    if (_controllerListener != null) {
      _controller.removeListener(_controllerListener!);
      _controllerListener = null;
    }

    unawaited(_deactivateScanner());
    _controller.dispose();
    _blackFade.dispose();

    super.dispose();
  }

  Future<void> _openLastScannedIfDemo() async {
    final raw = _lastRaw;
    if (raw == null || raw.isEmpty) return;

    // Only open the single-item page for the demo code
    if (raw != 'ABC-ABC-123') return;

    if (_navigating) return;
    _navigating = true;

    // Stop camera while inside the bucket page
    _enqueueCamera(_deactivateScanner);

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BucketItemPage(barcode: raw)));

    if (!mounted) return;
    _navigating = false;

    // Resume scanning when returning
    if (_isActive) {
      _resetFadeState();
      _enqueueCamera(_activateScanner);
    }
  }

  Future<bool> _openBucketIfDemo(String raw) async {
    if (raw != 'ABC-ABC-123') return false;
    if (_navigating) return true;

    _navigating = true;

    // Stop camera while inside the bucket page
    _enqueueCamera(_deactivateScanner);

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BucketItemPage(barcode: raw)));

    if (!mounted) return true;
    _navigating = false;

    // Resume scanning when returning
    if (_isActive) {
      _resetFadeState();
      _enqueueCamera(_activateScanner);
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final safe = MediaQuery.paddingOf(context);

    // BackdropFilter is expensive on Web. Keep look on mobile, skip blur on web.
    final allowBlur = !kIsWeb;

    // Overlays appear after fade is done (and only when active)
    final showOverlays = _isActive && _uiReady;

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
              // Keep scanner widget mounted (smoother switching)
              Positioned.fill(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeBottom: true,
                  removeLeft: true,
                  removeRight: true,
                  child: RepaintBoundary(
                    child: MobileScanner(
                      controller: _controller,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),

              // Hard-hide camera when not active (privacy + avoids last frame)
              if (!_isActive)
                const Positioned.fill(child: ColoredBox(color: Colors.black)),

              // Gradient overlay (cheap)
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

              // Snapchat-like fade: black cover that fades out when feed is ready.
              // (Only when active; when inactive we already hard-hide camera.)
              if (_isActive)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: AnimatedBuilder(
                      animation: _blackFade,
                      builder: (_, _) {
                        final a = _blackFade.value.clamp(0.0, 1.0);
                        if (a <= 0.001) return const SizedBox.shrink();
                        return ColoredBox(
                          color: Colors.black.withValues(alpha: a),
                        );
                      },
                    ),
                  ),
                ),

              // --- UI overlays (fade in quickly after snap fade ends) ---
              AnimatedOpacity(
                opacity: showOverlays ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !showOverlays,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
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
                                onTap:
                                    (_lastBucketLabel == null ||
                                        _lastRaw == null)
                                    ? null
                                    : _openLastScannedIfDemo,
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
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
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
                                  filter: ImageFilter.blur(
                                    sigmaX: 5,
                                    sigmaY: 5,
                                  ),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.08),
                                  ),
                                )
                              else
                                Container(
                                  color: Colors.black.withValues(alpha: 0.14),
                                ),
                              CustomPaint(
                                painter: _ScanFramePainter(
                                  cornerColor: AppColors.primary,
                                  borderColor: Colors.white.withValues(
                                    alpha: 0.42,
                                  ),
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
                          onPressed: () async {
                            _enqueueCamera(_deactivateScanner);

                            final code = await Navigator.of(context)
                                .push<String>(
                                  MaterialPageRoute(
                                    builder: (_) => const ManualEntryPage(),
                                  ),
                                );

                            if (!mounted) return;

                            if (code == null || code.trim().isEmpty) {
                              if (_isActive) {
                                _resetFadeState();
                                _enqueueCamera(_activateScanner);
                              }
                              return;
                            }

                            final now = DateTime.now();
                            setState(() {
                              _lastRaw = code;
                              _lastAt = now;
                              _lastBucketLabel = _bucketLabelFromRaw(code);
                            });

                            final opened = await _openBucketIfDemo(code);

                            if (!opened && _isActive) {
                              _resetFadeState();
                              _enqueueCamera(_activateScanner);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Permission helper overlay (show whenever active and permission missing)
              if (_isActive)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (_, state, _) {
                        if (state.hasCameraPermission) return const SizedBox();
                        return Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 18),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
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
