import '../../../core/utils/local_date.dart';

/// Lifecycle of a single daily occurrence.
enum OccurrenceStatus {
  /// Inside its window and not completed: notifications keep coming.
  active('active'),

  /// The user marked it as done. No more notifications for this date.
  completed('completed'),

  /// The window ended without completion.
  expired('expired');

  const OccurrenceStatus(this.dbValue);

  /// String stored in SQLite; shared with the Kotlin engine.
  final String dbValue;

  static OccurrenceStatus fromDb(String value) => OccurrenceStatus.values
      .firstWhere((s) => s.dbValue == value, orElse: () => active);
}

/// One concrete instance of a reminder on a given local date.
///
/// Rows are created lazily, the first time a notification fires for the date
/// (by the native engine) or when the user marks the reminder done before the
/// first notification (by the Flutter app).
class ReminderOccurrence {
  const ReminderOccurrence({
    required this.id,
    required this.reminderId,
    required this.date,
    required this.status,
    required this.windowStart,
    required this.windowEnd,
    required this.completedAt,
    required this.notificationCount,
    required this.lastNotifiedAt,
  });

  final int id;
  final int reminderId;

  /// Local calendar date on which the occurrence window started.
  final LocalDate date;
  final OccurrenceStatus status;

  /// UTC instants of the window this occurrence covered.
  final DateTime windowStart;
  final DateTime windowEnd;

  /// UTC instant, only set when [status] is [OccurrenceStatus.completed].
  final DateTime? completedAt;

  /// How many notifications were shown for this occurrence.
  final int notificationCount;
  final DateTime? lastNotifiedAt;

  bool get isCompleted => status == OccurrenceStatus.completed;
  bool get isClosed => status != OccurrenceStatus.active;

  @override
  String toString() =>
      'ReminderOccurrence(#$id reminder=$reminderId $date ${status.dbValue})';
}
