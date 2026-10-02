

class DoubleTapGuard {
  static final Map<String, int> _lastTaps = {};


  static bool allow(String key, {int thresholdMs = 600}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastTaps[key] ?? 0;
    if (now - last < thresholdMs) {
      return false;
    }
    _lastTaps[key] = now;
    return true;
  }


  static void reset(String key) {
    _lastTaps.remove(key);
  }
}

