import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scout_stock/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AppToast — Z-stacked, bottom-anchored, non-blocking notifications
// ═══════════════════════════════════════════════════════════════════════════
//
// Toasts stack on the Z-axis like a deck of cards above the nav bar.
// The newest toast is in front at full scale. Older toasts peek out
// behind — slightly scaled down, shifted up, and dimmed.
//
// Usage:
//   AppToast.of(context).show(AppToastData.success(
//     title: 'User Created',
//     subtitle: 'Ahmad  ·  ID #1287',
//   ));

// ── Data model ───────────────────────────────────────────────────────────

enum AppToastType { success, error }

class AppToastData {
  const AppToastData({
    required this.type,
    required this.title,
    this.subtitle,
    this.duration = const Duration(seconds: 4),
  });

  factory AppToastData.success({
    required String title,
    String? subtitle,
    Duration duration = const Duration(seconds: 4),
  }) => AppToastData(
    type: AppToastType.success,
    title: title,
    subtitle: subtitle,
    duration: duration,
  );

  factory AppToastData.error({
    required String title,
    String? subtitle,
    Duration duration = const Duration(seconds: 5),
  }) => AppToastData(
    type: AppToastType.error,
    title: title,
    subtitle: subtitle,
    duration: duration,
  );

  final AppToastType type;
  final String title;
  final String? subtitle;
  final Duration duration;
}

// ── Entry ────────────────────────────────────────────────────────────────

class _ToastEntry {
  _ToastEntry({required this.data}) : id = _nextId++;
  static int _nextId = 0;

  final int id;
  final AppToastData data;
}

// ── Controller ───────────────────────────────────────────────────────────

class AppToastController {
  AppToastController._();

  _AppToastOverlayState? _overlayState;

  void _attach(_AppToastOverlayState s) => _overlayState = s;
  void _detach(_AppToastOverlayState s) {
    if (_overlayState == s) _overlayState = null;
  }

  void show(AppToastData data) {
    _overlayState?._addToast(_ToastEntry(data: data));
  }
}

// ── InheritedWidget ──────────────────────────────────────────────────────

class AppToast extends InheritedWidget {
  const AppToast({super.key, required this.controller, required super.child});

  final AppToastController controller;

  static AppToastController of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<AppToast>();
    assert(w != null, 'No AppToast found. Wrap with AppToastOverlay.');
    return w!.controller;
  }

  @override
  bool updateShouldNotify(AppToast old) => controller != old.controller;
}

// ═══════════════════════════════════════════════════════════════════════════
// Overlay — place once at top of tree
// ═══════════════════════════════════════════════════════════════════════════

class AppToastOverlay extends StatefulWidget {
  const AppToastOverlay({
    super.key,
    required this.child,
    this.navBarHeight = 96,
  });

  final Widget child;

  /// Total bottom nav area height (bar + padding). Toasts sit above this.
  final double navBarHeight;

  @override
  State<AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<AppToastOverlay>
    with TickerProviderStateMixin {
  final _controller = AppToastController._();

  /// Ordered newest-first. Index 0 = front card.
  final _toasts = <_LiveToast>[];

  static const _maxVisible = 4;

  // Z-stack layout constants
  static const _stackOffsetY = 10.0;
  static const _stackScale = 0.04;
  static const _stackOpacity = 0.18;

  @override
  void initState() {
    super.initState();
    _controller._attach(this);
  }

  @override
  void dispose() {
    _controller._detach(this);
    for (final t in _toasts) {
      t.dispose();
    }
    super.dispose();
  }

  void _addToast(_ToastEntry entry) {
    final live = _LiveToast(
      entry: entry,
      vsync: this,
      onAutoDismiss: () => _dismiss(entry),
    );
    setState(() {
      _toasts.insert(0, live);
      while (_toasts.length > _maxVisible + 1) {
        final removed = _toasts.removeLast();
        removed.dispose();
      }
    });
    live.animateIn();
  }

  void _dismiss(_ToastEntry entry) {
    final idx = _toasts.indexWhere((t) => t.entry.id == entry.id);
    if (idx == -1) return;

    final live = _toasts[idx];
    live.animateOut().then((_) {
      if (!mounted) return;
      setState(() {
        _toasts.remove(live);
        live.dispose();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final bottomInset = safeBottom + widget.navBarHeight + 10;

    return AppToast(
      controller: _controller,
      child: Stack(
        children: [
          widget.child,

          if (_toasts.isNotEmpty)
            Positioned(
              left: 14,
              right: 14,
              bottom: bottomInset,
              // Reserve height for front card. Behind cards overflow
              // upward via Transform, so clip must be off.
              child: SizedBox(
                height: 74,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    for (
                      int i =
                          (_toasts.length > _maxVisible
                              ? _maxVisible
                              : _toasts.length) -
                          1;
                      i >= 0;
                      i--
                    )
                      _AnimatedZCard(
                        key: ValueKey(_toasts[i].entry.id),
                        live: _toasts[i],
                        depth: i,
                        isFront: i == 0,
                        onDismiss: () => _dismiss(_toasts[i].entry),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Live toast — owns animation controllers + auto-dismiss timer
// ═══════════════════════════════════════════════════════════════════════════

class _LiveToast {
  _LiveToast({
    required this.entry,
    required TickerProvider vsync,
    required this.onAutoDismiss,
  }) : entranceCtrl = AnimationController(
         vsync: vsync,
         duration: const Duration(milliseconds: 350),
       ),
       timerCtrl = AnimationController(
         vsync: vsync,
         duration: entry.data.duration,
       ) {
    timerCtrl.forward();
    _autoDismiss = Timer(entry.data.duration, onAutoDismiss);
  }

  final _ToastEntry entry;
  final VoidCallback onAutoDismiss;
  final AnimationController entranceCtrl;
  final AnimationController timerCtrl;
  Timer? _autoDismiss;
  bool _disposed = false;

  void animateIn() => entranceCtrl.forward();

  Future<void> animateOut() async {
    _autoDismiss?.cancel();
    if (!_disposed) await entranceCtrl.reverse();
  }

  void dispose() {
    _disposed = true;
    _autoDismiss?.cancel();
    entranceCtrl.dispose();
    timerCtrl.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Animated Z-card — positions each card at its depth
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedZCard extends StatelessWidget {
  const _AnimatedZCard({
    super.key,
    required this.live,
    required this.depth,
    required this.isFront,
    required this.onDismiss,
  });

  final _LiveToast live;
  final int depth;
  final bool isFront;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final entrance = CurvedAnimation(
      parent: live.entranceCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final targetScale = 1.0 - (depth * _AppToastOverlayState._stackScale);
    final targetOffsetY = -(depth * _AppToastOverlayState._stackOffsetY);
    final targetOpacity = (1.0 - (depth * _AppToastOverlayState._stackOpacity))
        .clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: entrance,
      builder: (context, child) {
        final progress = entrance.value;

        // Front card slides up from below. Behind cards sit still.
        final slideY = isFront ? 60.0 * (1.0 - progress) : 0.0;
        final fadeIn = isFront ? progress : 1.0;

        return Transform.translate(
          offset: Offset(0, targetOffsetY + slideY),
          child: AnimatedScale(
            scale: targetScale,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: targetOpacity * fadeIn,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: child,
            ),
          ),
        );
      },
      child: isFront
          ? Dismissible(
              key: ValueKey('swipe_${live.entry.id}'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => onDismiss(),
              child: _ToastCard(live: live, onDismiss: onDismiss),
            )
          : IgnorePointer(
              child: _ToastCard(live: live, onDismiss: onDismiss),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Toast card visual
// ═══════════════════════════════════════════════════════════════════════════

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.live, required this.onDismiss});

  final _LiveToast live;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final data = live.entry.data;

    final isSuccess = data.type == AppToastType.success;
    final accent = isSuccess ? AppColors.primary : const Color(0xFFE53935);
    final accentBg = accent.withValues(alpha: 0.08);
    final icon = isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 5, color: accent),
                const SizedBox(width: 14),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          data.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            fontSize: 14,
                          ),
                        ),
                        if (data.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            data.subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: AppColors.muted,
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    style: IconButton.styleFrom(
                      splashFactory: NoSplash.splashFactory,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: live.timerCtrl,
            builder: (context, _) {
              return LinearProgressIndicator(
                value: live.timerCtrl.value,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  accent.withValues(alpha: 0.25),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
