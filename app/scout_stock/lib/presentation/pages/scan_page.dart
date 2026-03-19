import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:scout_stock/presentation/widgets/app_toast.dart';
import 'package:scout_stock/router/app_routes.dart';

import '../../theme/app_theme.dart';
import '../widgets/admin_shell.dart';
import '../widgets/scout_shell.dart';

/// SSB-XXX-NNN where XXX = 3 uppercase letters, NNN = 3 digits.
final RegExp _ssbPattern = RegExp(r'^SSB-[A-Z]{3}-\d{3}$');

// ═══════════════════════════════════════════════════════════════════════════
// ScanPage — barcode scanner with camera lifecycle management
// ═══════════════════════════════════════════════════════════════════════════
//
// Key design decisions:
//
// 1. Tab detection: checks BOTH AdminShellScope and ScoutShellScope so the
//    camera properly deactivates/reactivates when switching tabs regardless
//    of user role.
//
// 2. Navigation guard: uses a cooldown timestamp instead of a boolean
//    `_navigating` flag. The old flag could get stuck `true` if
//    `context.push()` hung (e.g. after tab switching desync'd the
//    navigator context). A cooldown naturally expires.
//
// 3. Camera lifecycle: a single `_cameraActive` flag + serial queue. The
//    old code used 5 booleans (_starting, _stopping, _running, _feedReady,
//    _uiReady) that were hard to reason about.
//
// 4. Web compatibility: explicitly sets `facing: CameraFacing.back` and
//    uses `DetectionSpeed.normal` (not `.unrestricted`) to avoid
//    overwhelming older phone browsers.
// ═══════════════════════════════════════════════════════════════════════════

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ── Constants ──────────────────────────────────────────────────────────

  static const int _scanTabIndex = 0;

  /// Minimum time between two navigation pushes. Prevents double-push from
  /// rapid scans or tap + scan racing.
  static const Duration _navCooldown = Duration(milliseconds: 800);

  /// Minimum time between processing the same barcode value again.
  static const Duration _dedupeWindow = Duration(seconds: 2);

  // ── Camera ─────────────────────────────────────────────────────────────

  late final MobileScannerController _controller;
  StreamSubscription<BarcodeCapture>? _sub;

  /// Serial queue — ensures start/stop calls never overlap.
  Future<void> _cameraQueue = Future.value();

  /// Whether the camera is currently running (or starting).
  bool _cameraActive = false;

  // ── Tab tracking ───────────────────────────────────────────────────────

  ValueNotifier<int>? _tabIndex;

  /// Whether the scan tab is currently visible.
  bool _isActive = false;

  // ── Fade animation (black → camera feed) ───────────────────────────────

  late final AnimationController _fade;
  bool _feedVisible = false; // true once the fade completes
  bool _fading = false;

  // ── Barcode state ──────────────────────────────────────────────────────

  String? _lastRaw;
  DateTime? _lastScanAt;
  String? _lastBucketLabel;

  // ── Navigation guard ───────────────────────────────────────────────────

  DateTime? _lastNavAt;

  bool get _navOnCooldown {
    if (_lastNavAt == null) return false;
    return DateTime.now().difference(_lastNavAt!) < _navCooldown;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ═════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1.0, // starts fully black
    );

    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.code128],
      torchEnabled: false,
    );

    // Listen for camera ready → trigger fade.
    _controller.addListener(_onCameraStateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Resolve tab index from whichever shell scope is in the tree.
    // Admin users have AdminShellScope, scout users have ScoutShellScope.
    final next =
        AdminShellScope.maybeOf(context) ?? ScoutShellScope.maybeOf(context);

    if (!identical(_tabIndex, next)) {
      _tabIndex?.removeListener(_syncActiveState);
      _tabIndex = next;
      _tabIndex?.addListener(_syncActiveState);
    }

    _syncActiveState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isActive) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _enqueue(_startCamera);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _enqueue(_stopCamera);
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabIndex?.removeListener(_syncActiveState);
    _tabIndex = null;

    _controller.removeListener(_onCameraStateChanged);
    unawaited(_sub?.cancel());
    _sub = null;

    // Best-effort stop — don't await in dispose.
    unawaited(_controller.stop().catchError((_) {}));
    _controller.dispose();
    _fade.dispose();

    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Tab activation / deactivation
  // ═════════════════════════════════════════════════════════════════════════

  void _syncActiveState() {
    final shouldBeActive = _tabIndex == null
        ? true
        : _tabIndex!.value == _scanTabIndex;

    if (shouldBeActive == _isActive) return;
    _isActive = shouldBeActive;

    if (_isActive) {
      _resetFade();
      // Post-frame to let the widget tree settle after a tab switch.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isActive) _enqueue(_startCamera);
      });
    } else {
      _enqueue(_stopCamera);
      _resetFade();
    }

    if (mounted) setState(() {});
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Camera lifecycle (serialised via _cameraQueue)
  // ═════════════════════════════════════════════════════════════════════════

  void _enqueue(Future<void> Function() task) {
    _cameraQueue = _cameraQueue.then((_) => task()).catchError((_) {});
  }

  Future<void> _startCamera() async {
    if (!mounted || !_isActive || _cameraActive) return;

    _cameraActive = true;

    try {
      // Attach barcode stream (idempotent — only once).
      _sub ??= _controller.barcodes.listen(_onBarcodeCapture);

      // Small delay lets the MobileScanner widget mount its platform view
      // before we call start(). Helps older WebView / Safari.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      if (!mounted || !_isActive) {
        _cameraActive = false;
        return;
      }

      await _controller.start();

      // Wait for the video feed to actually produce frames.
      await _waitForVideoReady(timeout: const Duration(seconds: 3));

      if (mounted && _isActive && !_feedVisible) {
        _runFadeIn();
      }
    } catch (e) {
      debugPrint('ScanPage: camera start failed: $e');
      _cameraActive = false;

      // Even on failure, show the UI so the user can use manual entry.
      if (mounted) {
        _fade.value = 0.0;
        setState(() => _feedVisible = true);
      }
    }
  }

  Future<void> _stopCamera() async {
    if (!_cameraActive) return;

    try {
      await _sub?.cancel();
      _sub = null;
      await _controller.stop();
    } catch (_) {
      // Ignore — we're tearing down.
    }

    _cameraActive = false;
  }

  /// Polls `_controller.value` until the video is running or the timeout
  /// fires. Returns `true` if the camera is ready.
  Future<bool> _waitForVideoReady({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (mounted && _isActive) {
      final s = _controller.value;
      if (s.hasCameraPermission && s.isRunning) return true;
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    return false;
  }

  void _onCameraStateChanged() {
    if (!mounted || !_isActive) return;
    final s = _controller.value;
    if (s.hasCameraPermission && s.isRunning && !_feedVisible && !_fading) {
      _runFadeIn();
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Fade animation
  // ═════════════════════════════════════════════════════════════════════════

  void _resetFade() {
    _feedVisible = false;
    _fading = false;
    _fade.value = 1.0;
    if (mounted) setState(() {});
  }

  Future<void> _runFadeIn() async {
    if (_fading || _feedVisible) return;
    _fading = true;

    try {
      await _fade.animateTo(0.0, curve: Curves.easeOutCubic);
    } catch (_) {
      // AnimationController disposed — ignore.
    }

    _fading = false;
    if (mounted && _isActive) {
      setState(() => _feedVisible = true);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Barcode handling
  // ═════════════════════════════════════════════════════════════════════════

  void _onBarcodeCapture(BarcodeCapture capture) {
    if (!mounted || !_isActive) return;
    if (capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final now = DateTime.now();

    // Deduplicate: ignore the same value within the window.
    if (_lastRaw == raw &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < _dedupeWindow) {
      return;
    }
    _lastScanAt = now;

    final code = raw.trim().toUpperCase();

    if (!_ssbPattern.hasMatch(code)) {
      _lastRaw = raw; // track for dedup even if invalid
      if (mounted) {
        AppToast.of(context).show(
          AppToastData.error(
            title: 'Invalid barcode',
            subtitle: '"$raw" is not a valid bucket code (SSB-XXX-000)',
          ),
        );
      }
      return;
    }

    _lastRaw = code;
    setState(() => _lastBucketLabel = code);

    _navigateToBucket(code);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Navigation
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _navigateToBucket(String barcode) async {
    if (!mounted) return;
    if (_navOnCooldown) return;

    _lastNavAt = DateTime.now();

    // Stop camera before pushing — no need to keep it running off-screen.
    _enqueue(_stopCamera);

    try {
      // Use GoRouter.of(context) to get a stable router reference before
      // the async gap. This avoids issues where the State's context
      // becomes stale after tab switches in a StatefulShellRoute.
      final router = GoRouter.of(context);
      await router.push(AppRoutes.bucket(barcode));
    } catch (e) {
      debugPrint('ScanPage: navigation failed: $e');
    }

    // Returned from bucket page — restart camera if we're still active.
    if (!mounted) return;

    if (_isActive) {
      _resetFade();
      _enqueue(_startCamera);
    }
  }

  Future<void> _openLastScanned() async {
    final raw = _lastRaw;
    if (raw == null || raw.isEmpty) return;
    if (!_ssbPattern.hasMatch(raw)) return;
    await _navigateToBucket(raw);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Build
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final safe = MediaQuery.paddingOf(context);

    final allowBlur = !kIsWeb;
    final showOverlays = _isActive && _feedVisible;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;

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

          final maxFrameByH = usableH - reservedH;
          final maxFrameByW = w - sidePad * 2;

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
              // ── Camera preview ──────────────────────────────────────
              RepaintBoundary(
                child: MobileScanner(
                  controller: _controller,
                  fit: BoxFit.cover,
                ),
              ),

              // Black cover when tab is inactive.
              if (!_isActive)
                const Positioned.fill(child: ColoredBox(color: Colors.black)),

              // Gradient scrim (always visible over camera).
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

              // ── Fade-from-black overlay ─────────────────────────────
              if (_isActive)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _fade,
                      builder: (_, __) {
                        final a = _fade.value.clamp(0.0, 1.0);
                        if (a <= 0.001) return const SizedBox.shrink();
                        return ColoredBox(
                          color: Colors.black.withValues(alpha: a),
                        );
                      },
                    ),
                  ),
                ),

              // ── UI overlays ─────────────────────────────────────────
              AnimatedOpacity(
                opacity: showOverlays ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !showOverlays,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Last-scanned pill (top-left).
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
                                    : _openLastScanned,
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),

                      // Instruction text.
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

                      // Scan frame.
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

                      // Auto-scan pill.
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

                      // Manual entry button.
                      Positioned(
                        left: sidePad,
                        right: sidePad,
                        bottom: manualBottomInset,
                        height: manualBtnH,
                        child: _ManualEntryButton(
                          allowBlur: allowBlur,
                          onPressed: _onManualEntry,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Camera permission banner ────────────────────────────
              if (_isActive)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (_, state, __) {
                        if (state.hasCameraPermission) {
                          return const SizedBox.shrink();
                        }
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
                              'Camera permission needed to scan.\n'
                              'Check your browser site settings.',
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

  // ═════════════════════════════════════════════════════════════════════════
  // Manual entry
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _onManualEntry() async {
    _enqueue(_stopCamera);

    final router = GoRouter.of(context);
    final code = await router.push<String>(AppRoutes.manualEntry);

    if (!mounted) return;

    if (code == null || code.trim().isEmpty) {
      if (_isActive) {
        _resetFade();
        _enqueue(_startCamera);
      }
      return;
    }

    final upper = code.trim().toUpperCase();

    if (!_ssbPattern.hasMatch(upper)) {
      AppToast.of(context).show(
        AppToastData.error(
          title: 'Invalid bucket code',
          subtitle: '"$code" doesn\'t match SSB-XXX-000 format',
        ),
      );
      if (_isActive) {
        _resetFade();
        _enqueue(_startCamera);
      }
      return;
    }

    setState(() {
      _lastRaw = upper;
      _lastScanAt = DateTime.now();
      _lastBucketLabel = upper;
    });

    await _navigateToBucket(upper);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private widgets
// ═══════════════════════════════════════════════════════════════════════════

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
      onTap: enabled ? onTap : null,
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

    // Top-left
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

    // Top-right
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

    // Bottom-left
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

    // Bottom-right
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
