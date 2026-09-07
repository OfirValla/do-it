/// Days of the week, with the ISO numbering used by [DateTime.weekday].
enum Weekday {
  monday(1, 'Mon', 'Monday'),
  tuesday(2, 'Tue', 'Tuesday'),
  wednesday(3, 'Wed', 'Wednesday'),
  thursday(4, 'Thu', 'Thursday'),
  friday(5, 'Fri', 'Friday'),
  saturday(6, 'Sat', 'Saturday'),
  sunday(7, 'Sun', 'Sunday');

  const Weekday(this.isoValue, this.shortLabel, this.longLabel);

  /// Monday = 1 ... Sunday = 7.
  final int isoValue;
  final String shortLabel;
  final String longLabel;

  /// Bit used in the persisted bitmask: Monday = 1, Tuesday = 2, ... Sunday = 64.
  /// The same encoding is used by the Kotlin engine.
  int get bit => 1 << (isoValue - 1);

  static Weekday fromIso(int isoWeekday) => Weekday.values[isoWeekday - 1];

  static Weekday of(DateTime dateTime) => fromIso(dateTime.weekday);
}

/// An immutable set of weekdays, persisted as a 7-bit mask.
class DaysOfWeek {
  const DaysOfWeek(this.mask) : assert(mask >= 0 && mask <= 0x7F);

  factory DaysOfWeek.of(Iterable<Weekday> days) =>
      DaysOfWeek(days.fold(0, (mask, day) => mask | day.bit));

  static const DaysOfWeek none = DaysOfWeek(0);
  static const DaysOfWeek everyDay = DaysOfWeek(0x7F);
  static const DaysOfWeek weekdays = DaysOfWeek(0x1F);
  static const DaysOfWeek weekends = DaysOfWeek(0x60);

  /// Monday = bit 0 ... Sunday = bit 6.
  final int mask;

  bool contains(Weekday day) => (mask & day.bit) != 0;

  bool get isEmpty => mask == 0;
  bool get isNotEmpty => mask != 0;

  int get count => Weekday.values.where(contains).length;

  /// Days in Monday..Sunday order.
  List<Weekday> toList() => Weekday.values.where(contains).toList();

  DaysOfWeek withDay(Weekday day, bool selected) =>
      DaysOfWeek(selected ? mask | day.bit : mask & ~day.bit);

  DaysOfWeek toggle(Weekday day) => withDay(day, !contains(day));

  /// Human readable summary such as "Every day", "Weekdays", "Mon Wed Fri".
  String get label {
    if (mask == everyDay.mask) return 'Every day';
    if (mask == weekdays.mask) return 'Weekdays';
    if (mask == weekends.mask) return 'Weekends';
    if (isEmpty) return 'No days selected';
    final days = toList();
    if (days.length == 1) return days.single.longLabel;
    return days.map((d) => d.shortLabel).join(' ');
  }

  @override
  bool operator ==(Object other) => other is DaysOfWeek && other.mask == mask;

  @override
  int get hashCode => mask.hashCode;

  @override
  String toString() => 'DaysOfWeek($label)';
}
