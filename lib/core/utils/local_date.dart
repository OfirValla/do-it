/// A calendar date without time or timezone information.
///
/// Reminder occurrences are keyed by the local calendar date on which their
/// window starts, so this type is used throughout the scheduling layer instead
/// of [DateTime] to avoid accidentally mixing instants and wall-clock dates.
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// Builds the local date from the date components of [dateTime]
  /// (its timezone is irrelevant, only year/month/day are read).
  factory LocalDate.of(DateTime dateTime) =>
      LocalDate(dateTime.year, dateTime.month, dateTime.day);

  /// Parses an ISO-8601 date such as `2026-03-08`.
  factory LocalDate.parse(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) {
      throw FormatException('Invalid ISO date: $iso');
    }
    return LocalDate(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  /// ISO weekday: Monday = 1 ... Sunday = 7 (same as [DateTime.weekday]).
  int get weekday => DateTime.utc(year, month, day).weekday;

  LocalDate plusDays(int days) {
    final d = DateTime.utc(year, month, day).add(Duration(days: days));
    return LocalDate(d.year, d.month, d.day);
  }

  /// Number of whole days from this date to [other] (positive if [other] is
  /// later).
  int daysUntil(LocalDate other) {
    return DateTime.utc(other.year, other.month, other.day)
        .difference(DateTime.utc(year, month, day))
        .inDays;
  }

  /// Formats as `yyyy-MM-dd`, the representation stored in the database.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
