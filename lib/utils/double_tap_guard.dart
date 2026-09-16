/// Utility to prevent rapid double-clicks / multi-tap execution on buttons
/// across the PawWatch application.
class DoubleTapGuard {
  static final Map<String, int> _lastTaps = {};

  /// Returns `true` if enough time has passed since the last tap for [key].
  /// Default debounce threshold is 600ms.
  static bool allow(String key, {int thresholdMs = 600}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastTaps[key] ?? 0;
    if (now - last < thresholdMs) {
      return false;
    }
    _lastTaps[key] = now;
    return true;
  }

  /// Clears the recorded tap for [key], allowing an immediate retry
  /// (for example, if input validation failed before any network request).
  static void reset(String key) {
    _lastTaps.remove(key);
  }
}
