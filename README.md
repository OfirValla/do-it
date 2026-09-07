# Do It

> **Do It won't stop reminding you until it's done.**

Do It is a persistent reminder app for Android built with Flutter. You create a
reminder with a daily window ("08:00 – 18:00"), a repeat interval ("every 30
minutes") and the days it applies to. When the window opens, Android shows a
notification and keeps re-showing it at the interval until you tap **✓ Done**,
either on the notification itself or inside the app. Each notification can ring
like an alarm clock, with sound and vibration, for 1 to 5 minutes (per reminder)
until you tap Done or Stop. The next day starts a fresh occurrence.

Source: <https://github.com/OfirValla/do-it>

Everything that has to be reliable runs in native Android code driven by
`AlarmManager`. The Flutter process can be closed, swiped away, killed, the
phone can be locked, in Doze, or rebooted: notifications keep arriving and the
Done button keeps working.

---

## Contents

- [Quick start](#quick-start)
- [Architecture](#architecture)
- [The critical scenario](#the-critical-scenario)
- [Scheduling model](#scheduling-model)
- [Alarm-clock ringing](#alarm-clock-ringing)
- [Database](#database)
- [Android integration](#android-integration)
- [Permissions and reliability](#permissions-and-reliability)
- [Time and timezone handling](#time-and-timezone-handling)
- [Edge cases](#edge-cases)
- [Branding: icon and colours](#branding-icon-and-colours)
- [Project layout](#project-layout)
- [Tests](#tests)
- [Design decisions](#design-decisions)

---

## Quick start

Requirements

| Tool | Version |
| --- | --- |
| Flutter | 3.47 or newer (Dart 3.13+) |
| Android SDK | compileSdk 36, minSdk 26 (Android 8.0) |
| JDK | 17 |

```bash
git clone https://github.com/OfirValla/do-it.git
cd do-it
flutter pub get
dart run build_runner build          # generates lib/core/database/app_database.g.dart
flutter run                          # on a connected Android device / emulator
```

### Building the APK

A build script runs the whole pipeline (dependencies, Drift code generation,
`flutter analyze`, `flutter test`, `flutter build apk`) and copies the result to
`dist/do_it-<version>-<variant>.apk` with its SHA-256:

```powershell
# Windows
.\tool\build_apk.ps1                      # release, fat APK
.\tool\build_apk.ps1 -SplitPerAbi         # one APK per CPU architecture
.\tool\build_apk.ps1 -Mode debug -SkipTests
```

```bash
# macOS / Linux
tool/build_apk.sh
tool/build_apk.sh --split-per-abi
tool/build_apk.sh --debug --skip-tests
```

Or by hand: `flutter build apk --release` (or `flutter build appbundle`).

The generated Drift file is committed, so `build_runner` only needs to run
again after changing `lib/core/database/tables.dart`.

Open the `android/` folder in Android Studio to work on the Kotlin engine, or
open the project root in VS Code with the Flutter extension.

---

## Architecture

```
Flutter UI (Material 3, Riverpod)
        │
        ▼
ReminderService  ──►  ReminderRepository (Drift)  ──►  do_it.sqlite  ◄──┐
        │                                                                │
        ▼                                                                │
ReminderScheduler (Dart interface)                                       │
        │  platform channel "com.doit.app/engine"                        │
        ▼                                                                │
ReminderEngine (Kotlin)  ◄──  AlarmReceiver / NotificationActionReceiver │
        │                       / SystemEventReceiver (BOOT_COMPLETED …) │
        ├── SqliteReminderStore  ────────────────────────────────────────┘
        ├── AndroidAlarmGateway  ──► AlarmManager (one exact alarm per reminder)
        └── ReminderNotifier     ──► NotificationManager (one notification per reminder)
                │
                └── AlarmRingService (foreground) ──► alarm sound + vibration for 1–5 min
```

**Shared database, two runtimes.** Drift (Dart) and `SqliteReminderStore`
(Kotlin) open the same SQLite file (`<filesDir>/do_it.sqlite`) in WAL mode.
Drift owns the schema and migrations; Kotlin only reads and writes rows. This is
what lets the native engine make every decision on its own, with nothing but
the database as input, and what lets the Flutter UI show exactly what the
engine will do.

**Flutter never touches AlarmManager.** UI code calls `ReminderService`, which
writes to the repository and then calls the `ReminderScheduler` interface. The
Android implementation forwards `scheduleReminder(id)`, `cancelReminder(id)` and
`rescheduleAll()` over a single `MethodChannel`; the Kotlin engine reads the rule
from the database and sets the alarm.

**One alarm per reminder, always the next one.** When an alarm fires, the engine
shows the notification and immediately computes and schedules the next fire
time. No backlog, no thousands of alarms, and cancelling a reminder is a single
`AlarmManager.cancel`.

---

## The critical scenario

1. The user creates *Take vitamins, 08:00–18:00, every 30 min, Mon–Fri*.
   `ReminderService.create` inserts the row and calls `scheduleReminder(id)`.
   Kotlin computes the first fire (Monday 08:00) and sets one exact alarm.
2. The user closes the app. Android kills the process. Phone locked.
3. 08:00: `AlarmManager` wakes `AlarmReceiver` (process is started just for the
   receiver, no Flutter engine). `ReminderEngine.onAlarmFired`:
   - opens the SQLite file, loads the reminder,
   - creates the `occurrences` row for Monday with status `active`,
   - posts the notification with a **✓ Done** action and, because the
     reminder rings for 2 minutes, starts `AlarmRingService`, which loops the
     device's alarm sound, vibrates, wakes the lock screen and adds a **Stop**
     action; after 2 minutes (or Stop) the notification stays as a quiet
     reminder,
   - schedules the next alarm for 08:30.
4. 08:30, 09:00: same thing. The notification is updated in place (same id)
   and re-alerts. Nothing piles up in the tray.
5. 09:17: the user taps **✓ Done** on the lock screen. The action is a
   broadcast to `NotificationActionReceiver`; `ReminderEngine.complete`:
   - marks Monday's occurrence `completed` with `completed_at = 09:17`,
   - cancels the notification,
   - cancels the pending 09:30 alarm and schedules Tuesday 08:00.
6. Flutter was never involved. If the app happens to be open, the engine pings
   it over the channel (`onDataChanged`) and the UI refreshes its Drift
   streams; otherwise it re-reads the database on the next resume.
7. Tuesday 08:00: a new occurrence begins.

The JVM test `ReminderEngineTest.done from the notification stops today's
notifications and moves to tomorrow` exercises exactly this sequence against
in-memory fakes, and `ReminderServiceTest` covers the in-app Done path.

---

## Scheduling model

### Reminder

| Field | Storage | Notes |
| --- | --- | --- |
| `title`, `description` | text | |
| `startTime`, `endTime` | minutes since midnight | `end <= start` means the window crosses midnight |
| `intervalMinutes` | int | presets 5/10/15/30/60/120 or custom |
| `daysOfWeek` | 7-bit mask | Monday = 1 … Sunday = 64 (`DaysOfWeek` in Dart, `Rule.includes` in Kotlin) |
| `enabled` | bool | |
| `ringMinutes` | int | 0 = notification only, 1..5 = ring like an alarm clock (schema v2) |
| `createdAt`, `updatedAt` | epoch millis | |

### Occurrence

One row per (reminder, local date the window starts). Created lazily by the
first alarm, or by an in-app Done before the first alarm.

| Status | Meaning |
| --- | --- |
| `active` | Inside its window, not completed: notifications keep coming |
| `completed` | The user tapped Done. No more notifications for this date |
| `expired` | The window ended without completion (set by housekeeping) |

### `ScheduleCalculator` (Dart and Kotlin, identical semantics)

- `windowFor(rule, date)` – the occurrence window as two instants.
- `firesFor(rule, date)` – `start + k * interval` for every `k` inside the
  window (end included when it lands on the grid), resolved on the wall clock of
  the zone and de-duplicated.
- `currentWindow(rule, now)` – the window containing `now` (today's or
  yesterday's if it crosses midnight).
- `nextFireAfter(rule, after, isDateClosed)` – the first fire strictly after
  `after`, skipping dates whose occurrence is completed/expired. Looks back one
  day and ahead seven, so a single selected weekday is always found.

Both implementations are tested with the same scenarios
(`test/core/scheduling/schedule_calculator_test.dart` and
`android/app/src/test/.../ScheduleCalculatorTest.kt`).

### Notification and alarm ids

Exactly one alarm and at most one notification exist per reminder, so both use
the reminder's row id (`NotificationIds.kt`). The alarm, Done and Open
`PendingIntent`s share that request code but carry distinct actions and data
URIs (`doit://reminder/{id}/alarm`, `/done`, `/`), so Android treats them as
different intents. The occurrence date and intended fire time travel as extras
and are validated when the alarm is delivered, so a stale alarm never notifies
for the wrong day. Id 0 is reserved for the test notification in Settings.

---

## Alarm-clock ringing

Every reminder has an **alarm duration**: Off (a normal notification with the
channel's sound) or 1, 2, 3, 4 or 5 minutes. New reminders take the default
from Settings ("Default alarm duration").

When a notification fires for a ringing reminder, `ReminderNotifier` hands it
to `AlarmRingService`, a foreground service (type `mediaPlayback`) that:

- posts the reminder notification itself (same id, so nothing is duplicated)
  with **✓ Done** and **Stop** actions, category `ALARM`, on the silent
  `do_it_alarms` channel;
- loops the device's default alarm sound on the alarm audio stream
  (`USAGE_ALARM`, so the alarm volume and Do-Not-Disturb alarm rules apply)
  and vibrates with a repeating pattern;
- holds a partial wake lock for the ring duration;
- shows a full-screen intent that opens the reminder over the lock screen and
  turns the screen on (Android 14+ gates this behind "Full-screen
  notifications" special access, which Settings surfaces);
- stops after the ring duration, on **Stop** (the quiet notification stays and
  the next interval rings again), or on **Done** / disable / delete (the
  notification is removed).

Starting a foreground service from the background is allowed because the
trigger is an exact alarm the user scheduled. If Android refuses anyway
(inexact alarms on a restricted device), the engine falls back to a regular
high-priority notification, so a reminder is never lost. The "Test alarm"
button in Settings rings for one minute through the same path.

---

## Database

Drift with the `sqlite3` package (3.x, bundles SQLite via Dart hooks).

- `lib/core/database/tables.dart` – explicit table and column names, because
  Kotlin queries them by name.
- `lib/core/database/app_database.dart` – `schemaVersion` (currently 2:
  v2 added `reminders.ring_minutes`), `MigrationStrategy` (`onCreate:
  createAll`, numbered `onUpgrade` steps, `beforeOpen` enabling foreign keys)
  and `notifyExternalChange()` which re-runs all Drift streams after native
  writes. The Kotlin store tolerates columns added by newer schema versions
  until the app has migrated, because `BOOT_COMPLETED`/`MY_PACKAGE_REPLACED`
  can run the engine before the app is opened.
- `lib/core/database/database_connection.dart` – opens the file on a
  background isolate with `journal_mode = WAL` and a 5 s busy timeout. The path
  comes from Kotlin (`getDatabasePath`) so both sides open the same file.
- Repository queries: reminder CRUD, `getEnabled`, `watchOccurrencesSince`,
  `getOccurrencesOn(date)`, `getActiveOccurrences(now)`,
  `completeOccurrence` (select-then-write, mirrors Kotlin),
  `expireStaleOccurrences`.

Reminders survive app updates because the data lives in the app's private
files directory; `MY_PACKAGE_REPLACED` triggers a reschedule so alarms are
re-created after the update.

---

## Android integration

All Kotlin lives in `android/app/src/main/kotlin/com/doit/app/`:

| File | Role |
| --- | --- |
| `MainActivity.kt` | Hosts Flutter, wires the channel, forwards notification taps and permission results |
| `channel/EngineChannel.kt` | `MethodChannel` handler (schedule/cancel/rescheduleAll, permissions, settings intents, test notification, launch intent) |
| `channel/FlutterBridge.kt` | Lets receivers notify a live Flutter engine that data changed |
| `db/DoItDatabase.kt` | Location of the shared SQLite file |
| `db/ReminderStore.kt` | Store interface + row models mirroring the Drift tables |
| `db/SqliteReminderStore.kt` | `android.database.sqlite` implementation (WAL, no DDL) |
| `scheduling/ScheduleCalculator.kt` | Pure scheduling math (`java.time`) |
| `scheduling/ReminderEngine.kt` | Alarm fired / Done / scheduleNext / rescheduleAll – pure JVM, unit tested |
| `scheduling/AndroidAlarmGateway.kt` | `setExactAndAllowWhileIdle` with inexact fallback |
| `scheduling/Engine.kt` | Wires the engine, single background thread, `goAsync()` handling |
| `notifications/ReminderNotifier.kt` | Channels, notification content, **✓ Done** / **Stop** actions, full-screen intent |
| `notifications/AlarmRingService.kt` | Foreground service that rings (alarm sound + vibration) for the reminder's duration |
| `notifications/NotificationIds.kt` | Deterministic id strategy |
| `receivers/AlarmReceiver.kt` | `ACTION_FIRE` → `onAlarmFired` |
| `receivers/NotificationActionReceiver.kt` | `ACTION_DONE` → `complete`; `ACTION_STOP_RINGING` → silence |
| `receivers/SystemEventReceiver.kt` | `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIMEZONE_CHANGED`, `TIME_SET`, exact-alarm permission changes → `rescheduleAll` |
| `permissions/PermissionHelper.kt` | Permission state and settings deep links |

Receivers use `goAsync()` and a dedicated engine thread, so database work
happens off the main thread while Android keeps the wake lock until
`finish()`.

Manifest permissions: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `USE_FULL_SCREEN_INTENT`. The
only foreground service is the ringing alarm; scheduling itself needs none. No
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

---

## Permissions and reliability

The Settings screen shows three states and a one-line verdict:

| Check | How | Fix offered |
| --- | --- | --- |
| Notifications | `NotificationManagerCompat.areNotificationsEnabled()` | Android 13+: runtime dialog; otherwise app notification settings |
| Exact alarms | `AlarmManager.canScheduleExactAlarms()` (Android 12+) | "Alarms & reminders" special-access page |
| Battery optimisation | `PowerManager.isIgnoringBatteryOptimizations()` | Battery optimisation list (no extra permission needed) |
| Full-screen alarm (Android 14+) | `NotificationManager.canUseFullScreenIntent()` | "Full-screen notifications" special access |

The home screen shows a banner while notifications are off or exact alarms are
not allowed. Denied permissions never crash anything: without exact alarms the
engine falls back to `setAndAllowWhileIdle` and Settings explains that
reminders may arrive a few minutes late; without notification permission
alarms still keep the schedule so that everything resumes as soon as it is
granted (`SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` and the permission
result both trigger a reschedule).

Doze: `setExactAndAllowWhileIdle` fires at the exact minute even in Doze. Android
rate-limits allow-while-idle alarms to roughly one per 9 minutes per app while
in deep Doze, so a 5-minute interval may stretch while the phone lies untouched
and snaps back to the grid as soon as the device wakes.

"Test alarm (rings for 1 minute)" rings through the same code path real reminders use.

---

## Time and timezone handling

- Instants are stored as UTC epoch millis; wall-clock times as minutes since
  midnight; occurrence dates as ISO local dates.
- Dart uses the `timezone` package with the zone id reported by Android
  (`ZoneId.systemDefault()`), so predictions on screen match what the engine
  fires. Unknown vendor ids fall back to any zone with the same current offset.
- Kotlin uses `java.time` (`ZonedDateTime.of(LocalDateTime, ZoneId)`). The Dart
  calculator reproduces its gap/overlap rules explicitly instead of relying on
  package behaviour: non-existent times (spring forward) shift forward by the
  gap; ambiguous times (fall back) take the earlier offset; fires that collapse
  onto the same instant are de-duplicated. Result: no duplicate and no missing
  notifications across DST.
- Windows may cross midnight (`22:00 – 02:00`); the occurrence belongs to the
  date on which it starts.
- Timezone and clock changes are broadcast by Android; `SystemEventReceiver`
  rebuilds every alarm from the wall-clock rules in the new zone.

---

## Edge cases

| Case | Behaviour |
| --- | --- |
| User completes | Occurrence `completed`, notification removed, pending alarm replaced by next window's start |
| User disables | Alarm and notification cancelled |
| User enables | Next valid fire computed from now |
| User edits | Cancel → update DB → compute → schedule (ReminderService.update) |
| User deletes | Cancel alarm + notification, delete reminder and occurrences |
| Missed notifications (device off, Doze) | Only one alarm is ever pending; on delivery or reboot the engine schedules the next grid time from *now*. An alarm delivered after its window ended is dropped |
| Reboot | `BOOT_COMPLETED` → `rescheduleAll` (also on app start, to heal a force stop) |
| App update | `MY_PACKAGE_REPLACED` → `rescheduleAll`; data untouched |
| Timezone / time change | `TIMEZONE_CHANGED` / `TIME_SET` → `rescheduleAll` |
| DST | Wall-clock rules with de-duplication (tested for Berlin and New York transitions) |
| Notification permission denied | Banner + Settings; schedule kept |
| Exact alarm permission denied | Inexact fallback + explanation; automatic upgrade when granted |
| Done tapped after the window ended | Completes that day's occurrence (the notification carries its date) |
| Done tapped in the app before the first alarm | Creates the occurrence as completed; the engine skips the day |
| Stop tapped while ringing | Sound stops, notification stays, next interval rings again |
| Ring duration elapses | Same as Stop: quiet notification remains until Done or the next interval |

---

## Branding: icon and colours

**Launcher icon.** A bold white check on a violet-to-magenta gradient with a
mint dot (the dot of the "i" in *It*). Sources are SVG in `assets/icon/`
(`icon_full`, `icon_foreground`, `icon_background`, `icon_monochrome`);
`tool/generate_icons.py` renders them with headless Chrome at 1024 px and
writes every Android asset: legacy mipmaps, adaptive foreground/background
layers, the Android 13 monochrome (themed icon) layer and
`mipmap-anydpi-v26/ic_launcher.xml`.

```bash
pip install pillow
python tool/generate_icons.py            # re-render SVGs and regenerate mipmaps
python tool/generate_icons.py --no-render  # reuse the PNGs in assets/icon
```

The icon assets are not bundled with the app (they are not listed under
`flutter: assets:`).

**Colour scheme** (`lib/shared/theme/app_theme.dart`). One brand hue plus two
semantic accents, on Material 3 roles:

| Role | Light | Dark | Used for |
| --- | --- | --- | --- |
| Primary (violet) | `#6B4EFF` | `#B9ACFF` | buttons, FAB, active occurrence, selected chips |
| Tertiary (mint) | `#0B7F60` | `#3DF0BE` | completed states |
| Secondary (amber) | `#B25E00` | `#FFB866` | reliability warnings, permission banner |
| Surface | `#FBFAFF` | `#0F0E1A` | lavender-tinted white / deep navy-violet dark mode |

All overrides are paired with their `on*` colours and meet WCAG AA contrast.
The same violet is used for the notification accent (`ReminderNotifier.kt`)
and the dark splash background (`drawable-night/launch_background.xml`).

---

## Project layout

```
lib/
  main.dart                      bootstrap: platform channel, DB path, timezone, ProviderScope
  app.dart                       MaterialApp, lifecycle glue, native event handling
  core/
    database/                    Drift tables, AppDatabase, connection/path resolution
    notifications/               permission model + service
    platform/                    the single MethodChannel wrapper
    scheduling/                  ReminderRule, ScheduleCalculator, ReminderScheduler (+ Android impl)
    utils/                       LocalDate, LocalTime, Clock, Formatters, TimeZoneService
  features/
    reminders/
      domain/                    Reminder, ReminderOccurrence, DaysOfWeek, ReminderOverview
      data/                      ReminderRepository
      application/               ReminderService (use-cases)
      presentation/              providers, home / edit / detail screens, widgets
    settings/
      data/                      SettingsRepository (key/value table)
      presentation/              SettingsScreen
  shared/
    theme/                       Material 3 theme
    widgets/                     SectionHeader, StatusBadge, EmptyState, WeekdayStrip, PermissionBanner
android/app/src/main/kotlin/com/doit/app/   native engine (see table above)
android/app/src/test/kotlin/                JVM tests for the engine and calculator
assets/icon/                                 launcher icon sources (SVG + 1024 px PNG)
tool/build_apk.ps1, tool/build_apk.sh        one-command APK builds into dist/
tool/generate_icons.py                       renders the icon and writes all mipmaps
test/                                        Dart tests
```

---

## Tests

Dart:

```bash
flutter test
```

| File | Covers |
| --- | --- |
| `test/core/scheduling/schedule_calculator_test.dart` | daily / weekday / weekend / custom days, 5-min, 30-min, 1-hour intervals, start & end boundaries, midnight crossing, DST spring-forward and fall-back (Berlin, New York), timezone changes, closed-date skipping |
| `test/features/reminders/reminder_service_test.dart` | create/edit/enable/disable/delete ordering against the scheduler, alarm duration validation and persistence, stopRinging forwarding, Done completes today and moves to tomorrow, new day starts a new occurrence, housekeeping |
| `test/features/reminders/reminder_repository_test.dart` | CRUD, enabled query, today's/active occurrences, completion, cascade delete |
| `test/features/reminders/days_of_week_test.dart` | bitmask encoding shared with Kotlin, LocalDate/LocalTime |
| `test/core/utils/formatters_test.dart` | interval and "Next: …" labels |
| `test/widget/home_screen_test.dart` | empty state, active card with Done, add-reminder flow |

Kotlin (JVM, no device needed):

```bash
cd android
./gradlew :app:testDebugUnitTest
```

| File | Covers |
| --- | --- |
| `ScheduleCalculatorTest.kt` | same scenarios as the Dart calculator test |
| `ReminderEngineTest.kt` | alarm fired → notification + chained alarm; Done from notification cancels the rest of the day and starts tomorrow; Done before first alarm; disable/enable; edit replaces alarm; deleted reminder; **reboot restores alarms for enabled reminders only**; missed notifications produce no backlog; late delivery after the window; expiry housekeeping |

---

## Design decisions

- **Native engine instead of Flutter background execution.** Dart timers,
  isolates and background engines all die with the process. The only thing
  Android guarantees to keep is an `AlarmManager` alarm targeting a manifest
  `BroadcastReceiver`, so that is where the logic lives.
- **No `flutter_local_notifications`.** The plugin would need a background
  Flutter engine to handle actions and to chain the next alarm, which is
  heavier and less reliable than a Kotlin receiver. Since native code must
  post notifications anyway, a second notification stack would only add a
  second channel definition and a second id space. Notifications are created
  in one place (`ReminderNotifier.kt`).
- **A foreground service only for ringing.** Scheduling and the Done action
  never need one; the ring service exists because Android will not play
  minutes of audio from a receiver, and its notification doubles as the
  reminder notification so the user sees one thing.
- **Chain of single alarms** rather than pre-scheduling a day. It is
  self-healing (`rescheduleAll` on boot/start/time change), cannot produce a
  backlog, and needs one cancel per reminder.
- **Shared SQLite file** rather than a platform-channel copy of the data. Both
  runtimes are in the same process, WAL handles concurrent access, and the
  database is the single source of truth for what will happen next.
- **The same calculator in two languages, tested against the same
  expectations.** Duplication is deliberate: Dart needs it for the UI, Kotlin
  needs it with Flutter dead. The tests keep them honest.
