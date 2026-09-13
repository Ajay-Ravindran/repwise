# Workout App Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add daily weight tracking (with graphs) reachable from the Workout screen, replace the single "Time (seconds)" input with side-by-side Minutes/Seconds fields for time-based exercises, and keep the "Add Exercise" button pinned/visible in its selection sheet.

**Architecture:** A new `WeightEntry` model + pure bucketing/stats utility functions + `RepwiseProvider` additions (persisted via the existing JSON-file `RepwiseStorage`) back a new `WeightTrackingScreen` (pushed via `Navigator`, using `fl_chart` for the line graph). The Minutes/Seconds change is a mechanical UI + parsing swap applied identically in `workout_screen.dart` and `history_screen.dart` (both drive the same `WorkoutSetEntry.duration`). The Add Exercise sheet is restructured from one scrolling column into a fixed-height sheet with only the exercise checklist scrollable, so the button never scrolls off-screen.

**Tech Stack:** Flutter/Dart, `provider` package (existing state management), `fl_chart` (new dependency for the line graph), `flutter_test` (existing test conventions).

---

## Reference: existing conventions to follow

- Provider persistence: `RepwiseProvider._serializeState()` / `_applyStateFromMap()` / `_persist()` in `lib/providers/repwise_provider.dart`. New persisted collections are added as a new top-level JSON key, decoded via a `_decodeX(dynamic value)` helper, following the exact pattern used for `_muscleGroups` / `_completedSessions`.
- Models: plain Dart classes with `fromJson`/`toJson`, see `lib/models/exercise.dart` and `lib/models/workout.dart`.
- Provider unit tests: see `test/provider_navigation_test.dart` — a `_NoOpStorage extends RepwiseStorage` (or a capturing variant) is passed into `RepwiseProvider(storage: ...)`, and `provider.importFromJson(jsonString)` is used to seed state.
- Widget test: see `test/widget_test.dart` — `tester.pumpWidget(const RepwiseApp())`.

---

### Task 1: `WeightEntry` model

**Files:**
- Create: `lib/models/weight_entry.dart`
- Test: `test/weight_entry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/weight_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:repwise/models/weight_entry.dart';

void main() {
  group('WeightEntry', () {
    test('round-trips through toJson/fromJson', () {
      final entry = WeightEntry(
        id: 'w1',
        date: DateTime(2026, 6, 1),
        weight: 82.5,
        loggedAt: DateTime(2026, 6, 1, 8, 30),
      );

      final decoded = WeightEntry.fromJson(entry.toJson());

      expect(decoded.id, equals('w1'));
      expect(decoded.date, equals(DateTime(2026, 6, 1)));
      expect(decoded.weight, equals(82.5));
      expect(decoded.loggedAt, equals(DateTime(2026, 6, 1, 8, 30)));
    });

    test('copyWith overrides only the given fields', () {
      final entry = WeightEntry(
        id: 'w1',
        date: DateTime(2026, 6, 1),
        weight: 82.5,
        loggedAt: DateTime(2026, 6, 1, 8, 30),
      );

      final updated = entry.copyWith(weight: 81.0);

      expect(updated.id, equals('w1'));
      expect(updated.date, equals(DateTime(2026, 6, 1)));
      expect(updated.weight, equals(81.0));
      expect(updated.loggedAt, equals(DateTime(2026, 6, 1, 8, 30)));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/weight_entry_test.dart`
Expected: FAIL — `package:repwise/models/weight_entry.dart` does not exist (or `WeightEntry` undefined).

- [ ] **Step 3: Create the model**

```dart
// lib/models/weight_entry.dart

/// A single daily body-weight log entry. If a user logs their weight more
/// than once on the same [date], the latest value wins — callers (the
/// provider) are responsible for overwriting rather than duplicating.
class WeightEntry {
  WeightEntry({
    required this.id,
    required this.date,
    required this.weight,
    required this.loggedAt,
  });

  /// Unique identifier for this entry.
  final String id;

  /// The calendar day this weight applies to (time-of-day is not meaningful
  /// and should always be midnight).
  final DateTime date;

  /// The logged weight, in whatever unit (kg/lb) was active when logged.
  final double weight;

  /// The exact timestamp the entry was created/last overwritten.
  final DateTime loggedAt;

  WeightEntry copyWith({
    String? id,
    DateTime? date,
    double? weight,
    DateTime? loggedAt,
  }) {
    return WeightEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      weight: weight ?? this.weight,
      loggedAt: loggedAt ?? this.loggedAt,
    );
  }

  factory WeightEntry.fromJson(Map<String, dynamic> json) {
    return WeightEntry(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      weight: (json['weight'] as num).toDouble(),
      loggedAt: DateTime.parse(json['loggedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'date': date.toIso8601String(),
      'weight': weight,
      'loggedAt': loggedAt.toIso8601String(),
    };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/weight_entry_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/models/weight_entry.dart test/weight_entry_test.dart
git commit -m "feat: add WeightEntry model"
```

---

### Task 2: Weight chart/statistics pure utility functions

These are pure functions (no Flutter widget dependency) so they can be unit-tested directly, and are shared between the chart widget and the stats card.

**Files:**
- Create: `lib/utils/weight_chart_utils.dart`
- Test: `test/weight_chart_utils_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/weight_chart_utils_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:repwise/models/weight_entry.dart';
import 'package:repwise/utils/weight_chart_utils.dart';

WeightEntry _entry(String iso, double weight) {
  return WeightEntry(
    id: iso,
    date: DateTime.parse(iso),
    weight: weight,
    loggedAt: DateTime.parse(iso),
  );
}

void main() {
  group('bucketWeightEntries', () {
    test('day granularity returns one point per entry, sorted', () {
      final entries = [
        _entry('2026-06-02', 81.0),
        _entry('2026-06-01', 82.0),
      ];

      final points = bucketWeightEntries(entries, Granularity.day);

      expect(points.length, equals(2));
      expect(points[0].bucketStart, equals(DateTime(2026, 6, 1)));
      expect(points[0].weight, equals(82.0));
      expect(points[1].bucketStart, equals(DateTime(2026, 6, 2)));
      expect(points[1].weight, equals(81.0));
    });

    test('week granularity picks the lowest weight per ISO week', () {
      // 2026-06-01 is a Monday; 2026-06-03 is in the same week.
      final entries = [
        _entry('2026-06-01', 82.0),
        _entry('2026-06-03', 80.5),
        _entry('2026-06-08', 79.0), // next week (Monday)
      ];

      final points = bucketWeightEntries(entries, Granularity.week);

      expect(points.length, equals(2));
      expect(points[0].weight, equals(80.5));
      expect(points[0].bucketStart, equals(DateTime(2026, 6, 1)));
      expect(points[1].weight, equals(79.0));
      expect(points[1].bucketStart, equals(DateTime(2026, 6, 8)));
    });

    test('month granularity picks the lowest weight per calendar month', () {
      final entries = [
        _entry('2026-06-01', 82.0),
        _entry('2026-06-20', 79.5),
        _entry('2026-07-05', 80.0),
      ];

      final points = bucketWeightEntries(entries, Granularity.month);

      expect(points.length, equals(2));
      expect(points[0].weight, equals(79.5));
      expect(points[0].bucketStart, equals(DateTime(2026, 6, 1)));
      expect(points[1].weight, equals(80.0));
      expect(points[1].bucketStart, equals(DateTime(2026, 7, 1)));
    });

    test('returns an empty list for no entries', () {
      expect(bucketWeightEntries(const [], Granularity.day), isEmpty);
    });
  });

  group('formatBucketLabel', () {
    test('day/week use "d MMM", month uses "MMM yyyy"', () {
      final date = DateTime(2026, 6, 1);
      expect(formatBucketLabel(date, Granularity.day), equals('1 Jun'));
      expect(formatBucketLabel(date, Granularity.week), equals('1 Jun'));
      expect(formatBucketLabel(date, Granularity.month), equals('Jun 2026'));
    });
  });

  group('stats helpers', () {
    test('latestWeight returns the most recent entry weight', () {
      final entries = [_entry('2026-06-01', 82.0), _entry('2026-06-05', 80.0)];
      expect(latestWeight(entries), equals(80.0));
    });

    test('latestWeight returns null for no entries', () {
      expect(latestWeight(const []), isNull);
    });

    test('weightChangeOverDays compares latest to the closest entry at/before the cutoff', () {
      final entries = [
        _entry('2026-05-25', 84.0),
        _entry('2026-06-01', 82.0),
        _entry('2026-06-08', 80.0),
      ];

      // Reference = 2026-06-08, 7-day cutoff = 2026-06-01 -> baseline 82.0.
      final change = weightChangeOverDays(
        entries,
        7,
        referenceDate: DateTime(2026, 6, 8),
      );

      expect(change, equals(80.0 - 82.0));
    });

    test('weightChangeOverDays returns null when there is only one entry', () {
      final entries = [_entry('2026-06-01', 82.0)];
      expect(weightChangeOverDays(entries, 7), isNull);
    });

    test('minWeight and maxWeight scan all entries', () {
      final entries = [
        _entry('2026-06-01', 82.0),
        _entry('2026-06-05', 79.0),
        _entry('2026-06-08', 85.0),
      ];
      expect(minWeight(entries), equals(79.0));
      expect(maxWeight(entries), equals(85.0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/weight_chart_utils_test.dart`
Expected: FAIL — `package:repwise/utils/weight_chart_utils.dart` does not exist.

- [ ] **Step 3: Implement the utility functions**

```dart
// lib/utils/weight_chart_utils.dart
import '../models/weight_entry.dart';

enum Granularity { day, week, month }

/// One point to plot on the weight line chart.
class ChartPoint {
  ChartPoint({required this.bucketStart, required this.weight});

  final DateTime bucketStart;
  final double weight;
}

const List<String> _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

DateTime _dateOnly(DateTime dateTime) =>
    DateTime(dateTime.year, dateTime.month, dateTime.day);

DateTime _startOfWeek(DateTime date) {
  final dateOnly = _dateOnly(date);
  return dateOnly.subtract(Duration(days: dateOnly.weekday - DateTime.monday));
}

DateTime _startOfMonth(DateTime date) => DateTime(date.year, date.month, 1);

/// Buckets [entries] by [granularity]. For `day`, every entry becomes its
/// own point. For `week`/`month`, entries are grouped by ISO week / calendar
/// month and the **lowest** weight in each bucket is plotted, per the app's
/// weight-tracking spec. Returned points are sorted ascending by date.
List<ChartPoint> bucketWeightEntries(
  List<WeightEntry> entries,
  Granularity granularity,
) {
  if (entries.isEmpty) {
    return const <ChartPoint>[];
  }

  final sorted = List<WeightEntry>.from(entries)
    ..sort((a, b) => a.date.compareTo(b.date));

  if (granularity == Granularity.day) {
    return sorted
        .map(
          (entry) =>
              ChartPoint(bucketStart: _dateOnly(entry.date), weight: entry.weight),
        )
        .toList();
  }

  final DateTime Function(DateTime) bucketKeyFn =
      granularity == Granularity.week ? _startOfWeek : _startOfMonth;

  final Map<DateTime, double> lowestByBucket = <DateTime, double>{};
  for (final entry in sorted) {
    final key = bucketKeyFn(entry.date);
    final current = lowestByBucket[key];
    if (current == null || entry.weight < current) {
      lowestByBucket[key] = entry.weight;
    }
  }

  final sortedKeys = lowestByBucket.keys.toList()..sort();
  return sortedKeys
      .map((key) => ChartPoint(bucketStart: key, weight: lowestByBucket[key]!))
      .toList();
}

/// Formats a bucket's date for the chart's x-axis labels.
String formatBucketLabel(DateTime date, Granularity granularity) {
  switch (granularity) {
    case Granularity.day:
    case Granularity.week:
      return '${date.day} ${_monthAbbreviations[date.month - 1]}';
    case Granularity.month:
      return '${_monthAbbreviations[date.month - 1]} ${date.year}';
  }
}

/// The most recently logged weight, or null if there are no entries.
double? latestWeight(List<WeightEntry> entries) {
  if (entries.isEmpty) {
    return null;
  }
  final sorted = List<WeightEntry>.from(entries)
    ..sort((a, b) => a.date.compareTo(b.date));
  return sorted.last.weight;
}

/// The change in weight (latest - baseline) where baseline is the closest
/// entry at or before (`referenceDate` (defaults to the latest entry's date)
/// minus [days]). Returns null if there's no earlier entry to compare against.
double? weightChangeOverDays(
  List<WeightEntry> entries,
  int days, {
  DateTime? referenceDate,
}) {
  if (entries.length < 2) {
    return null;
  }
  final sorted = List<WeightEntry>.from(entries)
    ..sort((a, b) => a.date.compareTo(b.date));
  final latest = sorted.last;
  final reference = referenceDate ?? latest.date;
  final cutoff = reference.subtract(Duration(days: days));

  WeightEntry? baseline;
  for (final entry in sorted) {
    if (!entry.date.isAfter(cutoff)) {
      baseline = entry;
    } else {
      break;
    }
  }
  baseline ??= sorted.first;

  if (baseline.date.isAtSameMomentAs(latest.date)) {
    return null;
  }
  return latest.weight - baseline.weight;
}

/// The lowest weight ever logged, or null if there are no entries.
double? minWeight(List<WeightEntry> entries) {
  if (entries.isEmpty) {
    return null;
  }
  return entries.map((entry) => entry.weight).reduce((a, b) => a < b ? a : b);
}

/// The highest weight ever logged, or null if there are no entries.
double? maxWeight(List<WeightEntry> entries) {
  if (entries.isEmpty) {
    return null;
  }
  return entries.map((entry) => entry.weight).reduce((a, b) => a > b ? a : b);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/weight_chart_utils_test.dart`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/utils/weight_chart_utils.dart test/weight_chart_utils_test.dart
git commit -m "feat: add weight chart bucketing and stats utilities"
```

---

### Task 3: `RepwiseProvider` weight-tracking support

**Files:**
- Modify: `lib/providers/repwise_provider.dart`
- Test: `test/weight_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/weight_provider_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repwise/providers/repwise_provider.dart';
import 'package:repwise/utils/repwise_storage.dart';

/// Captures whatever was last written, so tests can assert on persistence,
/// and can be seeded to test that state survives a reload.
class _CapturingStorage extends RepwiseStorage {
  _CapturingStorage({Map<String, dynamic>? initialState})
      : _state = initialState;

  Map<String, dynamic>? _state;
  Map<String, dynamic>? get lastWritten => _state;

  @override
  Future<Map<String, dynamic>?> readState() async => _state;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {
    _state = state;
  }

  @override
  Future<File?> createExportFile(Map<String, dynamic> state) async => null;
}

void main() {
  group('RepwiseProvider weight tracking', () {
    test('logWeight adds a new entry for a day with no existing entry', () async {
      final provider = RepwiseProvider(storage: _CapturingStorage());
      await provider.initialize();

      provider.logWeight(82.5, date: DateTime(2026, 6, 1));

      expect(provider.weightEntries.length, equals(1));
      expect(provider.weightEntries.single.weight, equals(82.5));
      expect(provider.weightEntries.single.date, equals(DateTime(2026, 6, 1)));
    });

    test('logWeight overwrites the same day with the latest value', () async {
      final provider = RepwiseProvider(storage: _CapturingStorage());
      await provider.initialize();

      provider.logWeight(82.5, date: DateTime(2026, 6, 1));
      provider.logWeight(81.0, date: DateTime(2026, 6, 1));

      expect(provider.weightEntries.length, equals(1));
      expect(provider.weightEntries.single.weight, equals(81.0));
    });

    test('weightEntries is sorted ascending by date', () async {
      final provider = RepwiseProvider(storage: _CapturingStorage());
      await provider.initialize();

      provider.logWeight(80.0, date: DateTime(2026, 6, 5));
      provider.logWeight(82.0, date: DateTime(2026, 6, 1));

      final dates = provider.weightEntries.map((e) => e.date).toList();
      expect(dates, equals([DateTime(2026, 6, 1), DateTime(2026, 6, 5)]));
    });

    test('deleteWeightEntry removes the matching entry', () async {
      final provider = RepwiseProvider(storage: _CapturingStorage());
      await provider.initialize();
      provider.logWeight(82.5, date: DateTime(2026, 6, 1));
      final id = provider.weightEntries.single.id;

      provider.deleteWeightEntry(id);

      expect(provider.weightEntries, isEmpty);
    });

    test('weight entries persist across a reload of the same storage', () async {
      final storage = _CapturingStorage();
      final provider = RepwiseProvider(storage: storage);
      await provider.initialize();
      provider.logWeight(82.5, date: DateTime(2026, 6, 1));

      // Simulate app restart: new provider instance, same backing storage.
      final reloaded = RepwiseProvider(storage: storage);
      await reloaded.initialize();

      expect(reloaded.weightEntries.length, equals(1));
      expect(reloaded.weightEntries.single.weight, equals(82.5));
    });

    test('persisted state includes a weightEntries key with the logged entry', () async {
      final storage = _CapturingStorage();
      final provider = RepwiseProvider(storage: storage);
      await provider.initialize();

      provider.logWeight(82.5, date: DateTime(2026, 6, 1));
      // logWeight persists asynchronously (unawaited); wait for it to land.
      await Future<void>.delayed(Duration.zero);

      final written = storage.lastWritten;
      expect(written, isNotNull);
      expect(written!['weightEntries'], isA<List<dynamic>>());
      expect((written['weightEntries'] as List).length, equals(1));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/weight_provider_test.dart`
Expected: FAIL — `weightEntries`, `logWeight`, `deleteWeightEntry` undefined on `RepwiseProvider`.

- [ ] **Step 3: Add the model import and field**

In `lib/providers/repwise_provider.dart`, add the import alongside the other model imports:

```dart
import '../models/exercise.dart';
import '../models/muscle_group.dart';
import '../models/weight_entry.dart';
import '../models/workout.dart';
import '../utils/repwise_storage.dart';
```

Add the field next to `_completedSessions`:

```dart
  final List<MuscleGroup> _muscleGroups = <MuscleGroup>[];
  final List<WorkoutSession> _completedSessions = <WorkoutSession>[];
  final List<WeightEntry> _weightEntries = <WeightEntry>[];
```

- [ ] **Step 4: Add the public getter and mutators**

Add after the existing `completedSessions` getter (near the other getters):

```dart
  List<WeightEntry> get weightEntries {
    final sorted = List<WeightEntry>.from(_weightEntries)
      ..sort((a, b) => a.date.compareTo(b.date));
    return List<WeightEntry>.unmodifiable(sorted);
  }
```

Add near the other mutating methods (e.g. after `addMuscleGroup`, or any convenient spot at the class body level):

```dart
  /// Logs [weight] for [date] (defaults to today). If an entry already
  /// exists for that day, it is overwritten so the latest value wins.
  void logWeight(double weight, {DateTime? date}) {
    final day = _dateOnly(date ?? DateTime.now());
    final now = DateTime.now();
    final existingIndex = _weightEntries.indexWhere(
      (entry) => _dateOnly(entry.date) == day,
    );
    if (existingIndex >= 0) {
      _weightEntries[existingIndex] = _weightEntries[existingIndex].copyWith(
        weight: weight,
        loggedAt: now,
      );
    } else {
      _weightEntries.add(
        WeightEntry(id: _uuid.v4(), date: day, weight: weight, loggedAt: now),
      );
    }
    notifyListeners();
    unawaited(_persist());
  }

  /// Removes the weight entry with the given [id], if present.
  void deleteWeightEntry(String id) {
    final lengthBefore = _weightEntries.length;
    _weightEntries.removeWhere((entry) => entry.id == id);
    if (_weightEntries.length == lengthBefore) {
      return;
    }
    notifyListeners();
    unawaited(_persist());
  }
```

- [ ] **Step 5: Wire persistence — decode**

In `_applyStateFromMap`, add alongside the existing `_completedSessions` decode block:

```dart
    _completedSessions
      ..clear()
      ..addAll(_decodeSessions(map['completedSessions']));

    _weightEntries
      ..clear()
      ..addAll(_decodeWeightEntries(map['weightEntries']));
```

Add the decode helper next to `_decodeSessions`:

```dart
  List<WeightEntry> _decodeWeightEntries(dynamic value) {
    if (value is! List) {
      return <WeightEntry>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(WeightEntry.fromJson)
        .toList();
  }
```

- [ ] **Step 6: Wire persistence — encode**

In `_serializeState`, add the new key:

```dart
  Map<String, dynamic> _serializeState() {
    return <String, dynamic>{
      'muscleGroups': _muscleGroups.map((group) => group.toJson()).toList(),
      'completedSessions': _completedSessions
          .map((session) => session.toJson())
          .toList(),
      'weightEntries': _weightEntries.map((entry) => entry.toJson()).toList(),
      'activeSession': _activeSession?.toJson(),
```

(leave the rest of the map unchanged).

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/weight_provider_test.dart`
Expected: PASS (all tests)

- [ ] **Step 8: Run the full existing test suite to check for regressions**

Run: `flutter test`
Expected: All tests PASS (existing + new).

- [ ] **Step 9: Commit**

```bash
git add lib/providers/repwise_provider.dart test/weight_provider_test.dart
git commit -m "feat: add weight tracking to RepwiseProvider"
```

---

### Task 4: Add `fl_chart` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, add `fl_chart` alongside the other dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter

  cupertino_icons: ^1.0.8
  provider: ^6.1.2
  uuid: ^4.4.0
  table_calendar: ^3.0.9
  audioplayers: ^5.2.1
  path_provider: ^2.1.2
  share_plus: ^7.2.1
  file_picker: ^10.3.7
  fl_chart: ^0.68.0
```

- [ ] **Step 2: Fetch packages**

Run: `flutter pub get`
Expected: Exits 0; `fl_chart` resolved (check `pubspec.lock` now contains an `fl_chart` entry). If version `^0.68.0` fails to resolve against the installed Flutter/Dart SDK, relax to whatever `flutter pub get` reports as the latest compatible version and retry.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add fl_chart dependency for weight tracking graphs"
```

---

### Task 5: `WeightTrackingScreen`

**Files:**
- Create: `lib/screens/weight_tracking_screen.dart`

This screen is primarily UI wiring over the already-tested provider methods and utility functions from Tasks 1–3, so it is validated with `flutter analyze` plus a manual smoke check rather than exhaustive widget tests (widget test coverage for navigation is added in Task 6).

- [ ] **Step 1: Create the screen**

```dart
// lib/screens/weight_tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../models/weight_entry.dart';
import '../providers/repwise_provider.dart';
import '../utils/weight_chart_utils.dart';

const List<String> _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatFullDate(DateTime date) {
  return '${date.day} ${_monthAbbreviations[date.month - 1]} ${date.year}';
}

class WeightTrackingScreen extends StatefulWidget {
  const WeightTrackingScreen({super.key});

  @override
  State<WeightTrackingScreen> createState() => _WeightTrackingScreenState();
}

class _WeightTrackingScreenState extends State<WeightTrackingScreen> {
  Granularity _granularity = Granularity.day;
  final TextEditingController _weightController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  void _saveWeight(RepwiseProvider provider) {
    final parsed = double.tryParse(_weightController.text.trim());
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid weight')),
      );
      return;
    }
    provider.logWeight(parsed, date: _selectedDate);
    _weightController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Weight logged')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RepwiseProvider>();
    final entries = provider.weightEntries;
    final points = bucketWeightEntries(entries, _granularity);

    return Scaffold(
      appBar: AppBar(title: const Text('Weight Tracker')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Log weight',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Weight (${provider.weightUnit})',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _pickDate,
                          child: Text(_formatFullDate(_selectedDate)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _saveWeight(provider),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<Granularity>(
              segments: const [
                ButtonSegment(value: Granularity.day, label: Text('Day')),
                ButtonSegment(value: Granularity.week, label: Text('Week')),
                ButtonSegment(value: Granularity.month, label: Text('Month')),
              ],
              selected: <Granularity>{_granularity},
              onSelectionChanged: (selection) {
                setState(() => _granularity = selection.first);
              },
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: SizedBox(
                  height: 220,
                  child: points.isEmpty
                      ? const Center(
                          child: Text(
                            'No weight entries yet. Log your weight above to see progress.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _WeightLineChart(
                          points: points,
                          granularity: _granularity,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _StatsCard(entries: entries, unit: provider.weightUnit),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.entries, required this.unit});

  final List<WeightEntry> entries;
  final String unit;

  String _formatChange(double? value) {
    if (value == null) {
      return '—';
    }
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    final latest = latestWeight(entries);
    if (latest == null) {
      return const SizedBox.shrink();
    }
    final change7 = weightChangeOverDays(entries, 7);
    final change30 = weightChangeOverDays(entries, 30);
    final min = minWeight(entries);
    final max = maxWeight(entries);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _StatRow(
              label: 'Current weight',
              value: '${latest.toStringAsFixed(1)} $unit',
            ),
            _StatRow(label: 'Change (7 days)', value: _formatChange(change7)),
            _StatRow(
              label: 'Change (30 days)',
              value: _formatChange(change30),
            ),
            _StatRow(
              label: 'All-time min',
              value: min == null ? '—' : '${min.toStringAsFixed(1)} $unit',
            ),
            _StatRow(
              label: 'All-time max',
              value: max == null ? '—' : '${max.toStringAsFixed(1)} $unit',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _WeightLineChart extends StatelessWidget {
  const _WeightLineChart({required this.points, required this.granularity});

  final List<ChartPoint> points;
  final Granularity granularity;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].weight),
    ];
    final labels = [
      for (final point in points) formatBucketLabel(point.bucketStart, granularity),
    ];
    final weights = points.map((point) => point.weight).toList();
    final minY = weights.reduce((a, b) => a < b ? a : b);
    final maxY = weights.reduce((a, b) => a > b ? a : b);
    final verticalPadding = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.15;

    return LineChart(
      LineChartData(
        minY: minY - verticalPadding,
        maxY: maxY + verticalPadding,
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(labels[index], style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/screens/weight_tracking_screen.dart`
Expected: No errors (warnings about unused private members are not expected; investigate and fix anything reported).

- [ ] **Step 3: Commit**

```bash
git add lib/screens/weight_tracking_screen.dart
git commit -m "feat: add WeightTrackingScreen with logging, chart, and stats"
```

---

### Task 6: Entry point button on the Workout screen

**Files:**
- Modify: `lib/screens/workout_screen.dart:1507-1534` (`_buildHeader`)
- Test: `test/weight_tracking_navigation_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/weight_tracking_navigation_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:repwise/main.dart';

void main() {
  testWidgets('Track weight button opens the Weight Tracker screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RepwiseApp());
    await tester.pumpAndSettle();

    // Workout tab is index 1 in the bottom NavigationBar.
    await tester.tap(find.text('Workout').last);
    await tester.pumpAndSettle();

    final trackWeightButton = find.byTooltip('Track weight');
    expect(trackWeightButton, findsOneWidget);

    await tester.tap(trackWeightButton);
    await tester.pumpAndSettle();

    expect(find.text('Weight Tracker'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/weight_tracking_navigation_test.dart`
Expected: FAIL — no widget with tooltip "Track weight" found.

- [ ] **Step 3: Add the import**

In `lib/screens/workout_screen.dart`, add to the imports:

```dart
import '../providers/repwise_provider.dart';
import '../utils/workout_entry_formatter.dart';
import '../widgets/scrollable_metrics_text.dart';
import 'weight_tracking_screen.dart';
```

- [ ] **Step 4: Add the button to `_buildHeader`**

Replace the current `_buildHeader` body:

```dart
  Widget _buildHeader(
    BuildContext context,
    RepwiseProvider provider,
    WorkoutSession? session,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text('Workout', style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(width: 12),
        if (provider.isTimerActive)
          InkWell(
            onTap: () => _showTimerPopup(context),
            borderRadius: BorderRadius.circular(14),
            child: _TimerBadge(
              label: _formatClock(provider.timerRemaining ?? Duration.zero),
            ),
          ),
        if (provider.isTimerActive) const SizedBox(width: 8),
        IconButton(
          tooltip: provider.isTimerActive ? 'View timer' : 'Start timer',
          onPressed: () => _showTimerPopup(context),
          icon: Icon(
            provider.isTimerActive ? Icons.timer : Icons.timer_outlined,
          ),
        ),
      ],
    );
```

with:

```dart
  Widget _buildHeader(
    BuildContext context,
    RepwiseProvider provider,
    WorkoutSession? session,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text('Workout', style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Track weight',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const WeightTrackingScreen(),
            ),
          ),
          icon: const Icon(Icons.monitor_weight_outlined),
        ),
        if (provider.isTimerActive)
          InkWell(
            onTap: () => _showTimerPopup(context),
            borderRadius: BorderRadius.circular(14),
            child: _TimerBadge(
              label: _formatClock(provider.timerRemaining ?? Duration.zero),
            ),
          ),
        if (provider.isTimerActive) const SizedBox(width: 8),
        IconButton(
          tooltip: provider.isTimerActive ? 'View timer' : 'Start timer',
          onPressed: () => _showTimerPopup(context),
          icon: Icon(
            provider.isTimerActive ? Icons.timer : Icons.timer_outlined,
          ),
        ),
      ],
    );
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/weight_tracking_navigation_test.dart`
Expected: PASS

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/workout_screen.dart test/weight_tracking_navigation_test.dart
git commit -m "feat: add persistent weight-tracking entry point to Workout screen"
```

---

### Task 7: Minutes + Seconds input in `workout_screen.dart`

**Files:**
- Modify: `lib/screens/workout_screen.dart`

This changes the Add/Edit Set sheet used while logging a live workout. There is no isolated unit to TDD here (it's UI + inline parsing closures inside a `StatefulBuilder`), so this task is verified with `flutter analyze` and a targeted widget test that drives the sheet.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/time_entry_minutes_seconds_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:repwise/models/exercise.dart';
import 'package:repwise/models/muscle_group.dart';
import 'package:repwise/providers/repwise_provider.dart';
import 'package:repwise/screens/workout_screen.dart';
import 'package:repwise/utils/repwise_storage.dart';

class _NoOpStorage extends RepwiseStorage {
  const _NoOpStorage();

  @override
  Future<Map<String, dynamic>?> readState() async => null;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {}
}

Future<RepwiseProvider> _buildProviderWithTimeExercise() async {
  final provider = RepwiseProvider(storage: const _NoOpStorage());
  await provider.initialize();
  provider.addMuscleGroup('Core');
  final group = provider.muscleGroups.single;
  provider.addExercise(group.id, 'Plank', ExerciseUnit.time);
  provider.startWorkout();
  return provider;
}

void main() {
  testWidgets('Add Set sheet shows separate Minutes and Seconds fields', (
    WidgetTester tester,
  ) async {
    final provider = await _buildProviderWithTimeExercise();
    final group = provider.muscleGroups.single;
    final exercise = group.exercises.single;

    provider.startExercise(
      muscleGroupId: group.id,
      exerciseIds: [exercise.id],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<RepwiseProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => WorkoutScreen.showAddSetSheet(
                  context,
                  exerciseLog: provider.activeExercise!,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Minutes'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Seconds'), findsOneWidget);
    expect(find.text('Time (seconds)'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Minutes'),
      '1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Seconds'),
      '30',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add Set'));
    await tester.pumpAndSettle();

    final loggedSet = provider.activeExercise!.sets.single;
    expect(loggedSet.entries.single.duration, equals(const Duration(seconds: 90)));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/time_entry_minutes_seconds_test.dart`
Expected: FAIL — finds `Time (seconds)` field / no `Minutes`/`Seconds` fields yet.

- [ ] **Step 3: Update `_DraftSetEntry`**

Replace:

```dart
class _DraftSetEntry {
  _DraftSetEntry({required this.id, this.exerciseId});

  final String id;
  String? exerciseId;
  String reps = '';
  String weight = '';
  String distance = '';
  String time = '';
  String halfReps = '';
  String comment = '';
}
```

with:

```dart
class _DraftSetEntry {
  _DraftSetEntry({required this.id, this.exerciseId});

  final String id;
  String? exerciseId;
  String reps = '';
  String weight = '';
  String distance = '';
  String minutes = '';
  String seconds = '';
  String halfReps = '';
  String comment = '';
}
```

- [ ] **Step 4: Update pre-population from an existing entry**

Replace:

```dart
        if (entry.duration != null) {
          draft.time = entry.duration!.inSeconds.toString();
        }
```

with:

```dart
        if (entry.duration != null) {
          final totalSeconds = entry.duration!.inSeconds;
          draft.minutes = (totalSeconds ~/ 60).toString();
          draft.seconds = (totalSeconds % 60).toString();
        }
```

- [ ] **Step 5: Update the exercise-switch reset**

Replace:

```dart
                                        draft.reps = '';
                                        draft.weight = '';
                                        draft.distance = '';
                                        draft.time = '';
                                        draft.halfReps = '';
                                        draft.comment = '';
                                        validationError = null;
```

with:

```dart
                                        draft.reps = '';
                                        draft.weight = '';
                                        draft.distance = '';
                                        draft.minutes = '';
                                        draft.seconds = '';
                                        draft.halfReps = '';
                                        draft.comment = '';
                                        validationError = null;
```

- [ ] **Step 6: Add a `buildTimeRow()` helper next to `buildField`**

Immediately after the closing brace of `buildHalfRepsField()` (i.e., right before `Widget buildRepsRow() {`), insert:

```dart
                Widget buildTimeRow() {
                  Widget timeField({
                    required String label,
                    required String fieldKey,
                    required String initialValue,
                    required void Function(String) onChanged,
                  }) {
                    return TextFormField(
                      key: ValueKey('${draft.id}-$fieldKey-${exercise.id}'),
                      initialValue: initialValue,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: false,
                      ),
                      decoration: InputDecoration(
                        labelText: label,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          onChanged(value);
                          validationError = null;
                        });
                      },
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: timeField(
                            label: 'Minutes',
                            fieldKey: 'minutes',
                            initialValue: draft.minutes,
                            onChanged: (value) => draft.minutes = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: timeField(
                            label: 'Seconds',
                            fieldKey: 'seconds',
                            initialValue: draft.seconds,
                            onChanged: (value) => draft.seconds = value,
                          ),
                        ),
                      ],
                    ),
                  );
                }

```

- [ ] **Step 7: Replace each "Time (seconds)" field with `buildTimeRow()`**

Replace all four occurrences of this pattern (in the `ExerciseUnit.time`, `distanceTime`, `repsTime`, and `weightTime` switch cases):

```dart
                    fields.add(
                      buildField(
                        label: 'Time (seconds)',
                        fieldKey: 'time',
                        initialValue: draft.time,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        onChanged: (value) => draft.time = value,
                      ),
                    );
```

and

```dart
                      ..add(
                        buildField(
                          label: 'Time (seconds)',
                          fieldKey: 'time',
                          initialValue: draft.time,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          onChanged: (value) => draft.time = value,
                        ),
                      );
```

with, respectively:

```dart
                    fields.add(buildTimeRow());
```

and

```dart
                      ..add(buildTimeRow());
```

(Apply this to all 4 call sites: the `time` case's `fields.add(...)`, and the trailing `..add(...)` in `distanceTime`, `repsTime`, and `weightTime`.)

- [ ] **Step 8: Update duration parsing on save**

Replace:

```dart
                        Duration? parsePositiveDuration(String value) {
                          final seconds = parsePositiveInt(value);
                          if (seconds == null) {
                            return null;
                          }
                          return Duration(seconds: seconds);
                        }
```

with:

```dart
                        Duration? parsePositiveDuration(
                          String minutesInput,
                          String secondsInput,
                        ) {
                          int parseNonNegativeInt(String value) {
                            final trimmed = value.trim();
                            if (trimmed.isEmpty) {
                              return 0;
                            }
                            final parsed = int.tryParse(trimmed);
                            if (parsed == null || parsed < 0) {
                              return -1;
                            }
                            return parsed;
                          }

                          final minutesValue = parseNonNegativeInt(minutesInput);
                          final secondsValue = parseNonNegativeInt(secondsInput);
                          if (minutesValue < 0 || secondsValue < 0) {
                            return null;
                          }
                          final totalSeconds = minutesValue * 60 + secondsValue;
                          if (totalSeconds <= 0) {
                            return null;
                          }
                          return Duration(seconds: totalSeconds);
                        }
```

- [ ] **Step 9: Update the four call sites of `parsePositiveDuration`**

Replace every occurrence of:

```dart
                              duration = parsePositiveDuration(draft.time);
```

with:

```dart
                              duration = parsePositiveDuration(
                                draft.minutes,
                                draft.seconds,
                              );
```

(There are 4 occurrences: in the `time`, `distanceTime`, `repsTime`, and `weightTime` cases of the save-time switch statement.)

- [ ] **Step 10: Run the widget test to verify it passes**

Run: `flutter test test/time_entry_minutes_seconds_test.dart`
Expected: PASS

- [ ] **Step 11: Run `flutter analyze`**

Run: `flutter analyze lib/screens/workout_screen.dart`
Expected: No errors (in particular, no leftover references to `draft.time` or `parsePositiveDuration(draft.time)` with the old single-argument signature).

- [ ] **Step 12: Commit**

```bash
git add lib/screens/workout_screen.dart test/time_entry_minutes_seconds_test.dart
git commit -m "feat: split time entry into Minutes and Seconds fields on Workout screen"
```

---

### Task 8: Minutes + Seconds input in `history_screen.dart`

**Files:**
- Modify: `lib/screens/history_screen.dart`

Same change as Task 7, applied to the history-editing sheets, which share the `_DraftSetEntry` class and the top-level `_buildExerciseInputs`/`_parseDurationOrNull` functions.

- [ ] **Step 1: Update `_DraftSetEntry`**

Replace:

```dart
class _DraftSetEntry {
  _DraftSetEntry({required this.id, this.exerciseId});

  final String id;
  String? exerciseId;
  String reps = '';
  String weight = '';
  String distance = '';
  String time = '';
  String halfReps = '';
  String comment = '';
}
```

with:

```dart
class _DraftSetEntry {
  _DraftSetEntry({required this.id, this.exerciseId});

  final String id;
  String? exerciseId;
  String reps = '';
  String weight = '';
  String distance = '';
  String minutes = '';
  String seconds = '';
  String halfReps = '';
  String comment = '';
}
```

- [ ] **Step 2: Update both pre-population sites**

There are two occurrences (in `showHistorySetEditDialog` and the add-set-from-history function) of:

```dart
    if (entry.duration != null) {
      draft.time = entry.duration!.inSeconds.toString();
    }
```

Replace each with:

```dart
    if (entry.duration != null) {
      final totalSeconds = entry.duration!.inSeconds;
      draft.minutes = (totalSeconds ~/ 60).toString();
      draft.seconds = (totalSeconds % 60).toString();
    }
```

- [ ] **Step 3: Update the exercise-switch reset**

Replace:

```dart
                                        draft.reps = '';
                                        draft.weight = '';
                                        draft.distance = '';
                                        draft.time = '';
                                        draft.halfReps = '';
                                        draft.comment = '';
                                        validationError = null;
```

with:

```dart
                                        draft.reps = '';
                                        draft.weight = '';
                                        draft.distance = '';
                                        draft.minutes = '';
                                        draft.seconds = '';
                                        draft.halfReps = '';
                                        draft.comment = '';
                                        validationError = null;
```

- [ ] **Step 4: Replace `_parseDurationOrNull` with a two-argument combiner**

Replace:

```dart
Duration? _parseDurationOrNull(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final seconds = int.tryParse(trimmed);
  if (seconds == null || seconds <= 0) return null;
  return Duration(seconds: seconds);
}
```

with:

```dart
Duration? _combineMinutesSeconds(String minutesInput, String secondsInput) {
  int parseNonNegativeInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      return -1;
    }
    return parsed;
  }

  final minutesValue = parseNonNegativeInt(minutesInput);
  final secondsValue = parseNonNegativeInt(secondsInput);
  if (minutesValue < 0 || secondsValue < 0) {
    return null;
  }
  final totalSeconds = minutesValue * 60 + secondsValue;
  if (totalSeconds <= 0) {
    return null;
  }
  return Duration(seconds: totalSeconds);
}
```

- [ ] **Step 5: Update both call sites**

Replace each occurrence of:

```dart
                              final duration = _parseDurationOrNull(draft.time);
```

with:

```dart
                              final duration = _combineMinutesSeconds(
                                draft.minutes,
                                draft.seconds,
                              );
```

- [ ] **Step 6: Add a `buildTimeRow()` helper in `_buildExerciseInputs`**

Immediately after the closing brace of `buildHalfRepsField()` in `_buildExerciseInputs` (right before `Widget buildRepsRow() {`), insert:

```dart
  Widget buildTimeRow() {
    Widget timeField({
      required String label,
      required String fieldKey,
      required String initialValue,
      required void Function(String) onChanged,
    }) {
      return TextFormField(
        key: ValueKey('${draft.id}-$fieldKey-${exercise.id}'),
        initialValue: initialValue,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {
            onChanged(value);
          });
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: timeField(
              label: 'Minutes',
              fieldKey: 'minutes',
              initialValue: draft.minutes,
              onChanged: (value) => draft.minutes = value,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: timeField(
              label: 'Seconds',
              fieldKey: 'seconds',
              initialValue: draft.seconds,
              onChanged: (value) => draft.seconds = value,
            ),
          ),
        ],
      ),
    );
  }

```

- [ ] **Step 7: Replace each "Time (seconds)" field with `buildTimeRow()`**

Replace all four occurrences (in the `time`, `distanceTime`, `repsTime`, `weightTime` cases of the switch inside `_buildExerciseInputs`) of:

```dart
      fields.add(
        buildField(
          label: 'Time (seconds)',
          fieldKey: 'time',
          initialValue: draft.time,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          onChanged: (value) => draft.time = value,
        ),
      );
```

with:

```dart
      fields.add(buildTimeRow());
```

and replace all occurrences of:

```dart
        ..add(
          buildField(
            label: 'Time (seconds)',
            fieldKey: 'time',
            initialValue: draft.time,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            onChanged: (value) => draft.time = value,
          ),
        );
```

with:

```dart
        ..add(buildTimeRow());
```

- [ ] **Step 8: Run `flutter analyze`**

Run: `flutter analyze lib/screens/history_screen.dart`
Expected: No errors. In particular, no remaining references to `draft.time` or `_parseDurationOrNull`.

- [ ] **Step 9: Run the full test suite**

Run: `flutter test`
Expected: All tests PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/screens/history_screen.dart
git commit -m "feat: split time entry into Minutes and Seconds fields on History screen"
```

---

### Task 9: Pin the "Add Exercise" button in the exercise-selection sheet

**Files:**
- Modify: `lib/screens/workout_screen.dart` (`showStartExerciseSheet`, lines ~100–252)
- Test: `test/add_exercise_sheet_layout_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/add_exercise_sheet_layout_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:repwise/models/exercise.dart';
import 'package:repwise/providers/repwise_provider.dart';
import 'package:repwise/screens/workout_screen.dart';
import 'package:repwise/utils/repwise_storage.dart';

class _NoOpStorage extends RepwiseStorage {
  const _NoOpStorage();

  @override
  Future<Map<String, dynamic>?> readState() async => null;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {}
}

Future<RepwiseProvider> _buildProviderWithManyExercises() async {
  final provider = RepwiseProvider(storage: const _NoOpStorage());
  await provider.initialize();
  provider.addMuscleGroup('Legs');
  final group = provider.muscleGroups.single;
  for (var i = 0; i < 25; i++) {
    provider.addExercise(group.id, 'Leg exercise $i', ExerciseUnit.reps);
  }
  provider.startWorkout();
  return provider;
}

void main() {
  testWidgets(
    '"Add Exercise" button stays visible without scrolling when a muscle '
    'group has many exercises',
    (WidgetTester tester) async {
      final provider = await _buildProviderWithManyExercises();

      await tester.pumpWidget(
        ChangeNotifierProvider<RepwiseProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      WorkoutScreen.showStartExerciseSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The button must be immediately visible without any scrolling,
      // i.e. it renders within the (finite) test viewport straight away.
      expect(
        find.widgetWithText(FilledButton, 'Add Exercise'),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Add Exercise')).bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio),
      );
    },
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/add_exercise_sheet_layout_test.dart`
Expected: FAIL (or flaky/off-screen) because the button is inside the single scrollable column below 25 checkboxes.

- [ ] **Step 3: Restructure the sheet**

Replace the entire `builder: (sheetContext) { ... }` body of the `showModalBottomSheet` call in `showStartExerciseSheet` — i.e. everything from:

```dart
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              final group = groups.firstWhere(
                (candidate) => candidate.id == selectedGroupId,
              );
              final exercises = group.exercises;

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
```

through the matching closing:

```dart
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
```

with:

```dart
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.85,
            child: StatefulBuilder(
              builder: (context, setState) {
                final group = groups.firstWhere(
                  (candidate) => candidate.id == selectedGroupId,
                );
                final exercises = group.exercises;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
```

(then keep the existing header `Row`, description `Text`, and muscle-group `InputDecorator`/`DropdownButton` blocks exactly as they are, down through the `const SizedBox(height: 16)` that currently precedes `if (exercises.isEmpty) ... else Column(...)`),

then replace the exercise-list block:

```dart
                    if (exercises.isEmpty)
                      const Text(
                        'No exercises available for this muscle group yet.',
                      )
                    else
                      Column(
                        children: exercises.map((exercise) {
                          final isSelected = selectedExerciseIds.contains(
                            exercise.id,
                          );
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked ?? false) {
                                  selectedExerciseIds.add(exercise.id);
                                } else {
                                  selectedExerciseIds.remove(exercise.id);
                                }
                              });
                            },
                            title: Text(exercise.name),
                            subtitle: Text(exercise.unit.label),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 24),
```

with:

```dart
                    Expanded(
                      child: SingleChildScrollView(
                        child: exercises.isEmpty
                            ? const Text(
                                'No exercises available for this muscle group yet.',
                              )
                            : Column(
                                children: exercises.map((exercise) {
                                  final isSelected = selectedExerciseIds
                                      .contains(exercise.id);
                                  return CheckboxListTile(
                                    value: isSelected,
                                    onChanged: (checked) {
                                      setState(() {
                                        if (checked ?? false) {
                                          selectedExerciseIds.add(exercise.id);
                                        } else {
                                          selectedExerciseIds.remove(
                                            exercise.id,
                                          );
                                        }
                                      });
                                    },
                                    title: Text(exercise.name),
                                    subtitle: Text(exercise.unit.label),
                                  );
                                }).toList(),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
```

and keep the trailing `FilledButton.icon(... label: const Text('Add Exercise'))` exactly as-is, but close out the new wrapper widgets:

```dart
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
```

(i.e., the final `Column` returned by the `StatefulBuilder` closes with `);`, followed by the `StatefulBuilder`'s closing `},` `),`, then the `SizedBox`'s closing `),`, matching the added nesting from Step 3.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/add_exercise_sheet_layout_test.dart`
Expected: PASS

- [ ] **Step 5: Manually re-check the empty/short-list case still works**

Run: `flutter test` (full suite, including existing tests that exercise `showStartExerciseSheet` indirectly, if any)
Expected: All PASS — selecting a muscle group with 0 or few exercises still renders correctly (no overflow, empty-state text still shows, dropdown switching still clears `selectedExerciseIds`).

- [ ] **Step 6: Run `flutter analyze`**

Run: `flutter analyze lib/screens/workout_screen.dart`
Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/workout_screen.dart test/add_exercise_sheet_layout_test.dart
git commit -m "fix: pin Add Exercise button so it never scrolls out of view"
```

---

### Task 10: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Run static analysis on the whole project**

Run: `flutter analyze`
Expected: No errors (pre-existing warnings unrelated to this work, if any, are acceptable; do not introduce new ones).

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: All tests PASS, including every new test file added in Tasks 1–9.

- [ ] **Step 3: Manual smoke test (optional but recommended if a device/emulator is available)**

Run: `flutter run`
Checklist:
- Workout tab shows a weight icon button at all times (idle, active workout, timer running).
- Tapping it opens Weight Tracker; logging a weight today, then logging again today, results in only one entry (latest wins) — verified by checking the line chart still shows a single point for today after both logs.
- Switching Day/Week/Month on the Weight Tracker updates the chart granularity.
- Logging a time-based exercise (e.g., Plank) shows Minutes/Seconds side by side instead of "Time (seconds)".
- Opening "Add Exercise" for a muscle group with many exercises keeps the "Add Exercise" button visible without scrolling.

- [ ] **Step 4: Final commit (if any cleanup was needed)**

```bash
git status
```

If clean, no further commit is needed — every task already committed its own changes.
