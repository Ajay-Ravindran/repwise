# History & Workout Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 6 enhancements: calendar day navigation with muscle-group filtering, auto-navigate to most recent matching day, cancel workout session, exercise detail sheet with add-set in history, and selected-filter chip ordering.

**Architecture:** Three files are modified — `RepwiseProvider` gains three new data-layer methods; `HistoryScreen` gains navigation helpers, a custom calendar header, auto-jump logic, chip reordering, and an exercise detail sheet; `WorkoutScreen` gains a cancel-workout flow. One new test file exercises the pure provider logic.

**Tech Stack:** Flutter/Dart, `table_calendar ^3.0.9`, `provider ^6.1.2`, `flutter_test` (unit tests)

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Modify | `lib/providers/repwise_provider.dart` | Add `previousWorkoutDay`, `nextWorkoutDay`, `addSetToCompletedSession` |
| Modify | `lib/screens/history_screen.dart` | Features 1, 2, 3, 5, 6 |
| Modify | `lib/screens/workout_screen.dart` | Feature 4 (cancel workout) |
| Create | `test/provider_navigation_test.dart` | Unit tests for the three new provider methods |

---

## Task 1 — Provider navigation methods (TDD)

**Files:**
- Create: `test/provider_navigation_test.dart`
- Modify: `lib/providers/repwise_provider.dart`

- [ ] **Step 1 — Create failing tests**

Create `test/provider_navigation_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repwise/providers/repwise_provider.dart';
import 'package:repwise/utils/repwise_storage.dart';

class _NoOpStorage extends RepwiseStorage {
  const _NoOpStorage();

  @override
  Future<Map<String, dynamic>?> readState() async => null;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {}

  @override
  Future<File?> createExportFile(Map<String, dynamic> state) async => null;
}

const _muscleGroupId = 'mg-chest';
const _exerciseId = 'ex-bench';
const _altMuscleGroupId = 'mg-back';
const _altExerciseId = 'ex-row';

/// Builds a provider pre-loaded with sessions on specified dates.
/// [chestDates] and [backDates]: ISO-8601 date strings e.g. '2026-06-01'.
Future<RepwiseProvider> _buildProvider({
  List<String> chestDates = const [],
  List<String> backDates = const [],
}) async {
  int counter = 0;
  String nextId() => 'id-${counter++}';

  Map<String, dynamic> makeSession(
    String muscleGroupId,
    String exerciseId,
    String date,
  ) {
    final id = nextId();
    return {
      'id': 'session-$id',
      'startedAt': '${date}T10:00:00.000',
      'exercises': [
        {
          'id': 'exlog-$id',
          'muscleGroupId': muscleGroupId,
          'exerciseIds': [exerciseId],
          'startedAt': '${date}T10:00:00.000',
          'finishedAt': '${date}T10:30:00.000',
          'sets': [
            {
              'id': 'set-$id',
              'muscleGroupId': muscleGroupId,
              'timestamp': '${date}T10:00:00.000',
              'entries': [
                {'exerciseId': exerciseId, 'unit': 'reps', 'reps': 10},
              ],
            },
          ],
        },
      ],
    };
  }

  final sessions = [
    ...chestDates.map((d) => makeSession(_muscleGroupId, _exerciseId, d)),
    ...backDates.map((d) => makeSession(_altMuscleGroupId, _altExerciseId, d)),
  ];

  final json = jsonEncode({
    'muscleGroups': [
      {
        'id': _muscleGroupId,
        'name': 'Chest',
        'exercises': [
          {'id': _exerciseId, 'name': 'Bench Press', 'unit': 'reps'},
        ],
      },
      {
        'id': _altMuscleGroupId,
        'name': 'Back',
        'exercises': [
          {'id': _altExerciseId, 'name': 'Row', 'unit': 'reps'},
        ],
      },
    ],
    'completedSessions': sessions,
    'settings': {},
  });

  final provider = RepwiseProvider(storage: const _NoOpStorage());
  final success = await provider.importFromJson(json);
  expect(success, isTrue, reason: 'importFromJson should succeed');
  return provider;
}

DateTime _date(String iso) => DateTime.parse(iso);

void main() {
  group('previousWorkoutDay', () {
    test('returns the closest past day with any workout', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-01', '2026-06-05', '2026-06-10'],
      );
      expect(
        p.previousWorkoutDay(_date('2026-06-11')),
        equals(_date('2026-06-10')),
      );
    });

    test('ignores the boundary date itself (strictly before)', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-10', '2026-06-11'],
      );
      expect(
        p.previousWorkoutDay(_date('2026-06-11')),
        equals(_date('2026-06-10')),
      );
    });

    test('returns null when no workouts exist before the date', () async {
      final p = await _buildProvider(chestDates: ['2026-06-15']);
      expect(p.previousWorkoutDay(_date('2026-06-10')), isNull);
    });

    test('filters by muscleGroupIds when provided', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-01', '2026-06-05'],
        backDates: ['2026-06-08'],
      );
      expect(
        p.previousWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        equals(_date('2026-06-08')),
      );
    });

    test('ignores non-matching muscle groups when filter is active', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-05', '2026-06-09'],
        backDates: ['2026-06-08'],
      );
      expect(
        p.previousWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        equals(_date('2026-06-08')),
      );
    });

    test('returns null when filter matches no sessions before the date', () async {
      final p = await _buildProvider(backDates: ['2026-06-15']);
      expect(
        p.previousWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        isNull,
      );
    });
  });

  group('nextWorkoutDay', () {
    test('returns the closest future day with any workout', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-10', '2026-06-15', '2026-06-20'],
      );
      expect(
        p.nextWorkoutDay(_date('2026-06-09')),
        equals(_date('2026-06-10')),
      );
    });

    test('ignores the boundary date itself (strictly after)', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-10', '2026-06-11'],
      );
      expect(
        p.nextWorkoutDay(_date('2026-06-10')),
        equals(_date('2026-06-11')),
      );
    });

    test('returns null when no workouts exist after the date', () async {
      final p = await _buildProvider(chestDates: ['2026-06-01']);
      expect(p.nextWorkoutDay(_date('2026-06-10')), isNull);
    });

    test('filters by muscleGroupIds when provided', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-12'],
        backDates: ['2026-06-15'],
      );
      expect(
        p.nextWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        equals(_date('2026-06-15')),
      );
    });

    test('returns null when filter matches no sessions after the date', () async {
      final p = await _buildProvider(chestDates: ['2026-06-15']);
      expect(
        p.nextWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 2 — Run tests to verify they fail**

```
flutter test test/provider_navigation_test.dart
```

Expected: compilation error — `previousWorkoutDay` and `nextWorkoutDay` do not exist yet.

- [ ] **Step 3 — Add the methods to `RepwiseProvider`**

In `lib/providers/repwise_provider.dart`, add after the `sessionsForDay` method (around line 104):

```dart
  /// Returns the most-recent date strictly before [before] that has a
  /// logged workout. If [muscleGroupIds] is non-empty, only days where at
  /// least one exercise with a set matches a given muscle group are returned.
  DateTime? previousWorkoutDay(
    DateTime before, {
    Set<String> muscleGroupIds = const {},
  }) {
    final beforeDate = _dateOnly(before);
    // _completedSessions is stored newest-first, so the first match is the answer.
    for (final session in _completedSessions) {
      final sessionDate = _dateOnly(session.startedAt);
      if (!sessionDate.isBefore(beforeDate)) {
        continue;
      }
      if (_sessionMatchesMuscleGroups(session, muscleGroupIds)) {
        return sessionDate;
      }
    }
    return null;
  }

  /// Returns the earliest date strictly after [after] that has a logged
  /// workout. If [muscleGroupIds] is non-empty, only matching days are returned.
  DateTime? nextWorkoutDay(
    DateTime after, {
    Set<String> muscleGroupIds = const {},
  }) {
    final afterDate = _dateOnly(after);
    DateTime? result;
    for (final session in _completedSessions) {
      final sessionDate = _dateOnly(session.startedAt);
      if (!sessionDate.isAfter(afterDate)) {
        continue;
      }
      if (!_sessionMatchesMuscleGroups(session, muscleGroupIds)) {
        continue;
      }
      if (result == null || sessionDate.isBefore(result)) {
        result = sessionDate;
      }
    }
    return result;
  }

  bool _sessionMatchesMuscleGroups(
    WorkoutSession session,
    Set<String> muscleGroupIds,
  ) {
    if (muscleGroupIds.isEmpty) {
      return session.exercises.any((ex) => ex.hasSets);
    }
    return session.exercises.any(
      (ex) => ex.hasSets && muscleGroupIds.contains(ex.muscleGroupId),
    );
  }
```

- [ ] **Step 4 — Run tests to verify they pass**

```
flutter test test/provider_navigation_test.dart
```

Expected: all 11 tests PASS.

---

## Task 2 — Provider: `addSetToCompletedSession` (TDD)

**Files:**
- Modify: `test/provider_navigation_test.dart` (append a new group)
- Modify: `lib/providers/repwise_provider.dart`

- [ ] **Step 1 — Append failing tests to `test/provider_navigation_test.dart`**

Add these two imports at the top of the file if not already present:

```dart
import 'package:repwise/models/exercise.dart';
import 'package:repwise/models/workout.dart';
```

Append this group inside `main()` after the existing `nextWorkoutDay` group:

```dart
  group('addSetToCompletedSession', () {
    test('adds a set and returns true', () async {
      final p = await _buildProvider(chestDates: ['2026-06-01']);
      final session = p.completedSessions.first;
      final exerciseLog = session.exercises.first;
      final initialSetCount = exerciseLog.sets.length;

      final success = p.addSetToCompletedSession(
        sessionId: session.id,
        exerciseLogId: exerciseLog.id,
        entries: [
          WorkoutSetEntry(
            exerciseId: _exerciseId,
            unit: ExerciseUnit.reps,
            reps: 12,
          ),
        ],
      );

      expect(success, isTrue);
      final updatedLog = p.completedSessions.first.exercises.first;
      expect(updatedLog.sets.length, equals(initialSetCount + 1));
    });

    test('returns false for unknown session', () async {
      final p = await _buildProvider(chestDates: ['2026-06-01']);
      final session = p.completedSessions.first;
      final exerciseLog = session.exercises.first;

      final success = p.addSetToCompletedSession(
        sessionId: 'nonexistent-session',
        exerciseLogId: exerciseLog.id,
        entries: [
          WorkoutSetEntry(
            exerciseId: _exerciseId,
            unit: ExerciseUnit.reps,
            reps: 12,
          ),
        ],
      );

      expect(success, isFalse);
    });

    test('returns false for unknown exercise log', () async {
      final p = await _buildProvider(chestDates: ['2026-06-01']);
      final session = p.completedSessions.first;

      final success = p.addSetToCompletedSession(
        sessionId: session.id,
        exerciseLogId: 'nonexistent-log',
        entries: [
          WorkoutSetEntry(
            exerciseId: _exerciseId,
            unit: ExerciseUnit.reps,
            reps: 12,
          ),
        ],
      );

      expect(success, isFalse);
    });

    test('returns false when entries have no metrics', () async {
      final p = await _buildProvider(chestDates: ['2026-06-01']);
      final session = p.completedSessions.first;
      final exerciseLog = session.exercises.first;

      final success = p.addSetToCompletedSession(
        sessionId: session.id,
        exerciseLogId: exerciseLog.id,
        entries: [
          WorkoutSetEntry(
            exerciseId: _exerciseId,
            unit: ExerciseUnit.reps,
            reps: null, // no metrics
          ),
        ],
      );

      expect(success, isFalse);
    });
  });
```

- [ ] **Step 2 — Run tests to verify they fail**

```
flutter test test/provider_navigation_test.dart
```

Expected: compilation error — `addSetToCompletedSession` does not exist yet.

- [ ] **Step 3 — Add `addSetToCompletedSession` to `RepwiseProvider`**

In `lib/providers/repwise_provider.dart`, add this method after `removeSetFromCompletedSession` (around line 936):

```dart
  /// Adds a new set to an exercise log in a completed session.
  /// Returns false if the session, exercise, or entries are invalid.
  bool addSetToCompletedSession({
    required String sessionId,
    required String exerciseLogId,
    required List<WorkoutSetEntry> entries,
  }) {
    final sessionIndex = _completedSessions.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      return false;
    }
    final session = _completedSessions[sessionIndex];
    final exercise = _exerciseById(session, exerciseLogId);
    if (exercise == null) {
      return false;
    }
    final group = muscleGroupById(exercise.muscleGroupId);
    if (group == null) {
      return false;
    }
    final allowedIds = group.exercises.map((ex) => ex.id).toSet();
    final validEntries = entries
        .where(
          (entry) => entry.hasMetrics && allowedIds.contains(entry.exerciseId),
        )
        .toList(growable: false);
    if (validEntries.isEmpty) {
      return false;
    }
    final newIds = validEntries
        .map((entry) => entry.exerciseId)
        .where((id) => !exercise.exerciseIds.contains(id))
        .toSet();
    if (newIds.isNotEmpty) {
      exercise.exerciseIds.addAll(newIds);
    }
    final set = WorkoutSet(
      id: _uuid.v4(),
      muscleGroupId: exercise.muscleGroupId,
      entries: validEntries,
      timestamp: DateTime.now(),
    );
    exercise.sets.add(set);
    notifyListeners();
    unawaited(_persist());
    return true;
  }
```

- [ ] **Step 4 — Run all provider tests**

```
flutter test test/provider_navigation_test.dart
```

Expected: all 15 tests PASS.

---

## Task 3 — History: selected chips first (Feature 6)

**Files:**
- Modify: `lib/screens/history_screen.dart`

- [ ] **Step 1 — Replace `_getAllWorkoutMuscleGroups`**

Find this method in `_HistoryScreenState` (around line 462):

```dart
  List<MuscleGroup> _getAllWorkoutMuscleGroups(RepwiseProvider provider) {
    final Set<String> muscleGroupIds = <String>{};
    for (final session in provider.completedSessions) {
      for (final exercise in session.exercises) {
        if (exercise.hasSets) {
          muscleGroupIds.add(exercise.muscleGroupId);
        }
      }
    }
    final groups = muscleGroupIds
        .map((id) => provider.muscleGroupById(id))
        .whereType<MuscleGroup>()
        .toList();
    groups.sort((a, b) => a.name.compareTo(b.name));
    return groups;
  }
```

Replace it with:

```dart
  List<MuscleGroup> _getAllWorkoutMuscleGroups(RepwiseProvider provider) {
    final Set<String> muscleGroupIds = <String>{};
    for (final session in provider.completedSessions) {
      for (final exercise in session.exercises) {
        if (exercise.hasSets) {
          muscleGroupIds.add(exercise.muscleGroupId);
        }
      }
    }
    final groups = muscleGroupIds
        .map((id) => provider.muscleGroupById(id))
        .whereType<MuscleGroup>()
        .toList();

    final selected = groups
        .where((g) => _selectedMuscleGroupIds.contains(g.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final unselected = groups
        .where((g) => !_selectedMuscleGroupIds.contains(g.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return [...selected, ...unselected];
  }
```

- [ ] **Step 2 — Verify manually**

Run the app (`flutter run`). Go to History. Select a muscle group filter chip. Verify the selected chip immediately moves to the front of the filter bar. Deselect it — it returns to alphabetical order with the unselected chips.

---

## Task 4 — History: auto-navigate to most recent matching day (Feature 1)

**Files:**
- Modify: `lib/screens/history_screen.dart`

- [ ] **Step 1 — Add `_jumpToMostRecentMatchingDay` helper**

Add this method to `_HistoryScreenState` directly after `initState`:

```dart
  /// Jumps to the most recent workout day matching the current muscle group
  /// filter (or any workout day if no filter is active). No-ops if no day found.
  void _jumpToMostRecentMatchingDay() {
    if (!mounted) {
      return;
    }
    final provider = context.read<RepwiseProvider>();
    final now = DateTime.now();
    // Pass tomorrow so today is included in the search.
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final day = provider.previousWorkoutDay(
      tomorrow,
      muscleGroupIds: _selectedMuscleGroupIds,
    );
    if (day != null) {
      setState(() {
        _selectedDay = day;
        _focusedDay = day;
      });
    }
  }
```

- [ ] **Step 2 — Update `initState` postFrameCallback**

Find the existing `postFrameCallback` in `initState`:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<RepwiseProvider>();
      if (provider.autoFilterHistoryEnabled) {
        final muscleGroupId = provider.activeWorkoutMuscleGroupId;
        if (muscleGroupId != null) {
          setState(() {
            _selectedMuscleGroupIds.add(muscleGroupId);
          });
        }
      }
    });
```

Replace with:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<RepwiseProvider>();
      if (provider.autoFilterHistoryEnabled) {
        final muscleGroupId = provider.activeWorkoutMuscleGroupId;
        if (muscleGroupId != null) {
          setState(() {
            _selectedMuscleGroupIds.add(muscleGroupId);
          });
          _jumpToMostRecentMatchingDay();
        }
      }
    });
```

- [ ] **Step 3 — Update `FilterChip.onSelected` to jump when selecting a chip**

Find the `FilterChip.onSelected` in the filter chip bar (around line 382):

```dart
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedMuscleGroupIds.add(group.id);
                        } else {
                          _selectedMuscleGroupIds.remove(group.id);
                        }
                      });
                    },
```

Replace with:

```dart
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedMuscleGroupIds.add(group.id);
                        } else {
                          _selectedMuscleGroupIds.remove(group.id);
                        }
                      });
                      if (selected) {
                        _jumpToMostRecentMatchingDay();
                      }
                    },
```

- [ ] **Step 4 — Update auto-filter toggle in overflow menu**

Find the `Switch.onChanged` inside the auto-filter popup menu item (around line 211):

```dart
                                onChanged: (enabled) {
                                    provider.setAutoFilterHistoryEnabled(
                                      enabled,
                                    );
                                    // Update the menu state
                                    setMenuState(() {});
                                    // Apply or clear filter based on new state
                                    if (!enabled) {
                                      // Clear filter when disabled
                                      setState(() {
                                        _selectedMuscleGroupIds.clear();
                                      });
                                    } else {
                                      // Apply filter when enabled
                                      final muscleGroupId =
                                          provider.activeWorkoutMuscleGroupId;
                                      if (muscleGroupId != null) {
                                        setState(() {
                                          _selectedMuscleGroupIds.clear();
                                          _selectedMuscleGroupIds.add(
                                            muscleGroupId,
                                          );
                                        });
                                      }
                                    }
                                  },
```

Replace with:

```dart
                                onChanged: (enabled) {
                                    provider.setAutoFilterHistoryEnabled(
                                      enabled,
                                    );
                                    setMenuState(() {});
                                    if (!enabled) {
                                      setState(() {
                                        _selectedMuscleGroupIds.clear();
                                      });
                                    } else {
                                      final muscleGroupId =
                                          provider.activeWorkoutMuscleGroupId;
                                      if (muscleGroupId != null) {
                                        setState(() {
                                          _selectedMuscleGroupIds.clear();
                                          _selectedMuscleGroupIds.add(
                                            muscleGroupId,
                                          );
                                        });
                                        _jumpToMostRecentMatchingDay();
                                      }
                                    }
                                  },
```

- [ ] **Step 5 — Verify manually**

Run the app. Go to History. Select a muscle group filter chip — the calendar should jump to the most recent day where that muscle group was trained. Deselect the chip — the calendar stays on the current day (no auto-jump).

---

## Task 5 — History: custom arrow navigation (Features 2 & 3)

**Files:**
- Modify: `lib/screens/history_screen.dart`

- [ ] **Step 1 — Add `_navigateToPrevDay` and `_navigateToNextDay` methods**

Add these to `_HistoryScreenState` alongside `_jumpToMostRecentMatchingDay`:

```dart
  void _navigateToPrevDay() {
    final provider = context.read<RepwiseProvider>();
    final currentDay = _selectedDay ?? _focusedDay;
    final day = provider.previousWorkoutDay(
      currentDay,
      muscleGroupIds: _selectedMuscleGroupIds,
    );
    if (day != null) {
      setState(() {
        _selectedDay = day;
        _focusedDay = day;
      });
    }
  }

  void _navigateToNextDay() {
    final provider = context.read<RepwiseProvider>();
    final currentDay = _selectedDay ?? _focusedDay;
    final day = provider.nextWorkoutDay(
      currentDay,
      muscleGroupIds: _selectedMuscleGroupIds,
    );
    if (day != null) {
      setState(() {
        _selectedDay = day;
        _focusedDay = day;
      });
    }
  }
```

- [ ] **Step 2 — Add `_monthYearLabel` static helper**

Add alongside the existing `_formatDate` static helper in `_HistoryScreenState`:

```dart
  static String _monthYearLabel(DateTime day) {
    return '${_monthName(day.month)} ${day.year}';
  }
```

- [ ] **Step 3 — Update `HeaderStyle` inside the `TableCalendar`**

Find:

```dart
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                headerPadding: EdgeInsets.symmetric(vertical: 8),
              ),
```

Replace with:

```dart
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: false,
                leftChevronVisible: false,
                rightChevronVisible: false,
                headerPadding: EdgeInsets.symmetric(vertical: 4),
              ),
```

- [ ] **Step 4 — Add `headerTitleBuilder` to `calendarBuilders`**

Find the opening of `calendarBuilders`:

```dart
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
```

Replace with:

```dart
              calendarBuilders: CalendarBuilders(
                headerTitleBuilder: (ctx, focusedDay) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Previous workout',
                        onPressed: _navigateToPrevDay,
                      ),
                      Text(
                        _monthYearLabel(focusedDay),
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Next workout',
                        onPressed: _navigateToNextDay,
                      ),
                    ],
                  );
                },
                markerBuilder: (context, day, events) {
```

- [ ] **Step 5 — Verify manually**

Run the app. Go to History.
- **No filter:** Press `←` — should jump to the previous day that has any logged workout. Press `→` — should jump to the next day that has any logged workout. When the new day is in a different month, the calendar view should animate to that month.
- **With a muscle group filter active:** Same arrows should jump only between days where the selected muscle group(s) were trained.
- **Swipe on the calendar body** — month should still change as before (the `onPageChanged` callback updates `_focusedDay`).
- **No more workouts in that direction:** Arrow press does nothing.

---

## Task 6 — Workout: cancel workout session (Feature 4)

**Files:**
- Modify: `lib/screens/workout_screen.dart`

- [ ] **Step 1 — Add `_handleCancelWorkout` to `_WorkoutScreenState`**

Add this method alongside `_handleFinishWorkout` (around line 1886):

```dart
  Future<void> _handleCancelWorkout(
    BuildContext context,
    RepwiseProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Workout?'),
          content: const Text(
            'This workout has no sets logged and will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    provider.finishWorkout(); // Discards the session because no sets exist.
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Workout cancelled'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 250,
          left: 16,
          right: 16,
        ),
      ),
    );
  }
```

- [ ] **Step 2 — Replace the bottom button in `_buildActiveWorkoutBody`**

Find:

```dart
        OutlinedButton(
          onPressed: hasLoggedSets
              ? () => _handleFinishWorkout(context, provider)
              : null,
          child: const Text('Finish Workout'),
        ),
```

Replace with:

```dart
        if (hasLoggedSets)
          OutlinedButton(
            onPressed: () => _handleFinishWorkout(context, provider),
            child: const Text('Finish Workout'),
          )
        else
          OutlinedButton.icon(
            onPressed: () => _handleCancelWorkout(context, provider),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel Workout'),
          ),
```

- [ ] **Step 3 — Verify manually**

Run the app.
1. Start a workout. Without adding any sets, verify a **"Cancel Workout"** button (with close icon) appears at the bottom.
2. Tap it — confirm dialog appears with "Back" and "Discard".
3. Tap "Back" — dialog closes, workout still active.
4. Tap "Cancel Workout" again, then "Discard" — snackbar "Workout cancelled" appears; screen returns to "Ready to start your workout?" state.
5. Start a workout again, add at least one set — verify "Cancel Workout" is gone and "Finish Workout" appears.

---

## Task 7 — History: exercise detail sheet with Add Set (Feature 5)

**Files:**
- Modify: `lib/screens/history_screen.dart`

- [ ] **Step 1 — Add `onTap` parameter to `_ExerciseHistorySection`**

Find the class declaration and constructor:

```dart
class _ExerciseHistorySection extends StatelessWidget {
  const _ExerciseHistorySection({
    required this.log,
    required this.provider,
    required this.sessionId,
    this.showMuscleGroup = true,
  });

  final WorkoutExerciseLog log;
  final RepwiseProvider provider;
  final String sessionId;
  final bool showMuscleGroup;
```

Replace with:

```dart
class _ExerciseHistorySection extends StatelessWidget {
  const _ExerciseHistorySection({
    required this.log,
    required this.provider,
    required this.sessionId,
    this.showMuscleGroup = true,
    this.onTap,
  });

  final WorkoutExerciseLog log;
  final RepwiseProvider provider;
  final String sessionId;
  final bool showMuscleGroup;
  final VoidCallback? onTap;
```

- [ ] **Step 2 — Wrap the exercise chips header with `InkWell` in `_ExerciseHistorySection.build`**

Find the non-superset chip row:

```dart
        if (!log.isSuperset) ...[
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...exerciseNames.map((name) => Chip(label: Text(name))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (log.isSuperset) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Chip(label: Text('Superset')),
          ),
        ],
```

Replace with:

```dart
        if (!log.isSuperset) ...[
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...exerciseNames.map((name) => Chip(label: Text(name))),
                      if (onTap != null)
                        const Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (log.isSuperset) ...[
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Chip(label: Text('Superset')),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 16),
                ],
              ),
            ),
          ),
        ],
```

- [ ] **Step 3 — Wire up `onTap` from `_SessionCard._buildExercisesList`**

In `_SessionCard._buildExercisesList`, find:

```dart
      widgets.add(
        _ExerciseHistorySection(
          log: log,
          provider: provider,
          sessionId: session.id,
          showMuscleGroup: false,
        ),
      );
```

Replace with:

```dart
      widgets.add(
        _ExerciseHistorySection(
          log: log,
          provider: provider,
          sessionId: session.id,
          showMuscleGroup: false,
          onTap: () => showHistoryExerciseDetailSheet(
            context,
            exerciseLog: log,
            sessionId: session.id,
          ),
        ),
      );
```

- [ ] **Step 4 — Add `_exerciseNamesForLog` top-level helper**

Add this function near the bottom of `history_screen.dart` (before or after `showHistorySetEditDialog`):

```dart
List<String> _exerciseNamesForLog(
  WorkoutExerciseLog log,
  RepwiseProvider provider,
) {
  final ids = <String>{...log.exerciseIds};
  for (final set in log.sets) {
    for (final entry in set.entries) {
      ids.add(entry.exerciseId);
    }
  }
  final names = ids
      .map((id) => provider.exerciseById(id)?.name)
      .whereType<String>()
      .toList();
  names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names;
}
```

- [ ] **Step 5 — Add `showHistoryExerciseDetailSheet` top-level function**

Add this function after `_exerciseNamesForLog`:

```dart
void showHistoryExerciseDetailSheet(
  BuildContext context, {
  required WorkoutExerciseLog exerciseLog,
  required String sessionId,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) {
          return Consumer<RepwiseProvider>(
            builder: (ctx, provider, _) {
              // Re-fetch live data so the sheet rebuilds when sets change.
              WorkoutSession? session;
              WorkoutExerciseLog? log;
              for (final s in provider.completedSessions) {
                if (s.id == sessionId) {
                  session = s;
                  break;
                }
              }
              if (session != null) {
                for (final e in session.exercises) {
                  if (e.id == exerciseLog.id) {
                    log = e;
                    break;
                  }
                }
              }

              if (log == null) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('This exercise is no longer available.'),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }

              final group = provider.muscleGroupById(log.muscleGroupId);
              final exerciseNames = _exerciseNamesForLog(log, provider);
              final canAddSet = group != null && group.exercises.isNotEmpty;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  children: [
                    // Drag handle
                    const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 4),
                      child: SizedBox(
                        width: 40,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFBDBDBD),
                            borderRadius: BorderRadius.all(
                              Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Header row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (group != null)
                                  Chip(label: Text(group.name)),
                                if (log.isSuperset)
                                  const Chip(label: Text('Superset')),
                                ...exerciseNames.map(
                                  (name) => Chip(label: Text(name)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),
                    // Sets list
                    Expanded(
                      child: log.sets.isEmpty
                          ? const Center(
                              child: Text(
                                'No sets logged for this exercise.',
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                8,
                              ),
                              itemCount: log.sets.length,
                              itemBuilder: (listCtx, index) {
                                return _WorkoutSetTile(
                                  set: log!.sets[index],
                                  setNumber: index + 1,
                                  provider: provider,
                                  sessionId: sessionId,
                                  exerciseLogId: log.id,
                                );
                              },
                            ),
                    ),
                    // Footer
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: canAddSet
                          ? FilledButton.icon(
                              onPressed: () => showAddSetToHistorySheet(
                                context,
                                sessionId: sessionId,
                                exerciseLog: log!,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Set'),
                            )
                          : const Text(
                              'The muscle group for this exercise has been '
                              'removed from the library. Sets cannot be added.',
                              textAlign: TextAlign.center,
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}
```

- [ ] **Step 6 — Add `showAddSetToHistorySheet` top-level function**

Add this function after `showHistoryExerciseDetailSheet`:

```dart
void showAddSetToHistorySheet(
  BuildContext context, {
  required String sessionId,
  required WorkoutExerciseLog exerciseLog,
}) {
  final rootContext = context;
  final provider = rootContext.read<RepwiseProvider>();
  final group = provider.muscleGroupById(exerciseLog.muscleGroupId);
  if (group == null) {
    ScaffoldMessenger.of(rootContext).showSnackBar(
      const SnackBar(
        content: Text('Muscle group for this exercise is missing'),
      ),
    );
    return;
  }

  final Map<String, Exercise> exercisesById = <String, Exercise>{
    for (final exercise in group.exercises) exercise.id: exercise,
  };
  for (final id in exerciseLog.exerciseIds) {
    final cached = provider.exerciseById(id);
    if (cached != null) {
      exercisesById.putIfAbsent(id, () => cached);
    }
  }

  var draftCounter = 0;
  String nextDraftId() => 'draft_${draftCounter++}';
  final List<_DraftSetEntry> drafts = <_DraftSetEntry>[];

  // Pre-populate from the last set (same behaviour as active-workout add-set).
  if (exerciseLog.sets.isNotEmpty) {
    final lastSet = exerciseLog.sets.last;
    for (final entry in lastSet.entries) {
      final draft = _DraftSetEntry(
        id: nextDraftId(),
        exerciseId: entry.exerciseId,
      );
      if (entry.reps != null) draft.reps = entry.reps!.toString();
      if (entry.weight != null) {
        draft.weight = _formatNumberToString(entry.weight!);
      }
      if (entry.distance != null) {
        draft.distance = _formatNumberToString(entry.distance!);
      }
      if (entry.duration != null) {
        draft.time = entry.duration!.inSeconds.toString();
      }
      if (entry.halfReps != null && entry.halfReps! > 0) {
        draft.halfReps = entry.halfReps!.toString();
      }
      drafts.add(draft);
    }
  }

  if (drafts.isEmpty) {
    final defaultIds = exerciseLog.exerciseIds
        .where((id) => exercisesById.containsKey(id))
        .toList();
    if (defaultIds.isEmpty && exercisesById.isNotEmpty) {
      defaultIds.add(exercisesById.keys.first);
    }
    for (final id in defaultIds) {
      drafts.add(_DraftSetEntry(id: nextDraftId(), exerciseId: id));
    }
    if (drafts.isEmpty) {
      drafts.add(_DraftSetEntry(id: nextDraftId()));
    }
  }

  String? validationError;

  showModalBottomSheet<void>(
    context: rootContext,
    isScrollControlled: true,
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
            Exercise? resolveExercise(String? exerciseId) {
              if (exerciseId == null) return null;
              return exercisesById[exerciseId] ??
                  provider.exerciseById(exerciseId);
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Add Set',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(group.name)),
                      if (exerciseLog.isSuperset)
                        const Chip(label: Text('Superset')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...drafts.asMap().entries.map((mapEntry) {
                    final index = mapEntry.key;
                    final draft = mapEntry.value;
                    final exercise = resolveExercise(draft.exerciseId);
                    final bool canRemove = drafts.length > 1;
                    final bool isMissingExercise =
                        draft.exerciseId != null && exercise == null;

                    return Card(
                      key: ValueKey(draft.id),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: draft.exerciseId,
                                    decoration: InputDecoration(
                                      labelText: drafts.length > 1
                                          ? 'Exercise ${index + 1}'
                                          : 'Exercise',
                                      border: const OutlineInputBorder(),
                                      errorText: isMissingExercise
                                          ? 'Exercise not found'
                                          : null,
                                    ),
                                    items: exercisesById.entries
                                        .map(
                                          (e) => DropdownMenuItem<String>(
                                            value: e.key,
                                            child: Text(e.value.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (exerciseId) {
                                      setState(() {
                                        draft.exerciseId = exerciseId;
                                        draft.reps = '';
                                        draft.weight = '';
                                        draft.distance = '';
                                        draft.time = '';
                                        draft.halfReps = '';
                                        draft.comment = '';
                                        validationError = null;
                                      });
                                    },
                                  ),
                                ),
                                if (canRemove) ...[
                                  const SizedBox(width: 12),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        drafts.removeAt(index);
                                      });
                                    },
                                    icon: const Icon(Icons.remove_circle),
                                    tooltip: 'Remove exercise',
                                  ),
                                ],
                              ],
                            ),
                            if (exercise != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      exercise.unit.label,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    ..._buildExerciseInputs(
                                      context,
                                      exercise,
                                      draft,
                                      provider,
                                      setState,
                                      validationError,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        final newEntry = _DraftSetEntry(id: nextDraftId());
                        if (drafts.isNotEmpty) {
                          newEntry.exerciseId = drafts.last.exerciseId;
                        } else if (exercisesById.isNotEmpty) {
                          newEntry.exerciseId = exercisesById.keys.first;
                        }
                        drafts.add(newEntry);
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add another exercise entry'),
                  ),
                  if (validationError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        validationError!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Add Set'),
                          onPressed: () {
                            void showError(String message) {
                              setState(() {
                                validationError = message;
                              });
                            }

                            if (drafts.isEmpty) {
                              showError('Add at least one exercise entry.');
                              return;
                            }

                            final entries = <WorkoutSetEntry>[];
                            for (final draft in drafts) {
                              final exerciseId = draft.exerciseId;
                              if (exerciseId == null) {
                                showError(
                                  'Select an exercise for each entry.',
                                );
                                return;
                              }
                              final exercise = resolveExercise(exerciseId);
                              if (exercise == null) {
                                showError('Selected exercise is unavailable.');
                                return;
                              }

                              final reps = _parseIntOrNull(draft.reps);
                              final weight =
                                  _parseDoubleOrNull(draft.weight);
                              final distance =
                                  _parseDoubleOrNull(draft.distance);
                              final duration =
                                  _parseDurationOrNull(draft.time);
                              final halfReps =
                                  _parseIntOrNull(draft.halfReps);
                              final trimmedComment = draft.comment.trim();

                              bool hasData;
                              switch (exercise.unit) {
                                case ExerciseUnit.weightReps:
                                  hasData =
                                      weight != null && reps != null;
                                  break;
                                case ExerciseUnit.reps:
                                  hasData = reps != null;
                                  break;
                                case ExerciseUnit.time:
                                  hasData = duration != null;
                                  break;
                                case ExerciseUnit.distanceTime:
                                  hasData =
                                      distance != null && duration != null;
                                  break;
                                case ExerciseUnit.repsTime:
                                  hasData =
                                      reps != null && duration != null;
                                  break;
                                case ExerciseUnit.distance:
                                  hasData = distance != null;
                                  break;
                                case ExerciseUnit.weightTime:
                                  hasData =
                                      weight != null && duration != null;
                                  break;
                              }

                              if (!hasData) {
                                showError(
                                  'Fill in all required fields for ${exercise.name}.',
                                );
                                return;
                              }

                              entries.add(
                                WorkoutSetEntry(
                                  exerciseId: exerciseId,
                                  unit: exercise.unit,
                                  reps: reps,
                                  weight: weight,
                                  distance: distance,
                                  duration: duration,
                                  halfReps:
                                      (halfReps != null && halfReps > 0)
                                      ? halfReps
                                      : null,
                                  comment: trimmedComment.isEmpty
                                      ? null
                                      : trimmedComment,
                                ),
                              );
                            }

                            final success =
                                provider.addSetToCompletedSession(
                                  sessionId: sessionId,
                                  exerciseLogId: exerciseLog.id,
                                  entries: entries,
                                );

                            if (!success) {
                              showError('Unable to add this set.');
                              return;
                            }

                            Navigator.of(sheetContext).pop();
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              const SnackBar(
                                content: Text('Set added'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
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

- [ ] **Step 7 — Run all tests**

```
flutter test
```

Expected: all tests PASS (existing `widget_test.dart` + 15 tests in `provider_navigation_test.dart`).

- [ ] **Step 8 — Verify manually**

Run the app. Go to History. Select a day with logged workouts. Find a session card with exercises.
1. Tap on an exercise's name chip — a bottom sheet opens showing the exercise's sets (with PR icons, comment expand, etc.), an "Add Set" button, and a close button.
2. Tap "Add Set" — an add-set sheet opens pre-populated with the last set's values. Enter new values and tap "Add Set" — the set appears in the detail sheet immediately (the sheet rebuilds via `Consumer`). A "Set added" snackbar shows.
3. Tap an existing set tile in the detail sheet — the edit/delete dialog still works correctly.
4. For an exercise whose muscle group was deleted from the library: the "Add Set" button should be absent, replaced by the explanatory text.
