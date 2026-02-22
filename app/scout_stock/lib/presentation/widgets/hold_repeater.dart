import 'dart:async';
import 'dart:math' as math;

class HoldRepeater {
  HoldRepeater({required int maxCount, required this.onTick})
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
