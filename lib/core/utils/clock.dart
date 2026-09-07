/// Source of the current instant. Injected so that scheduling logic and
/// presentation code can be tested deterministically.
abstract class Clock {
  const Clock();

  /// The current instant, always expressed in UTC.
  DateTime nowUtc();
}

class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// A clock frozen at (or manually advanced from) a fixed instant.
class FixedClock extends Clock {
  FixedClock(DateTime now) : _now = now.toUtc();

  DateTime _now;

  @override
  DateTime nowUtc() => _now;

  void set(DateTime now) => _now = now.toUtc();

  void advance(Duration duration) => _now = _now.add(duration);
}
