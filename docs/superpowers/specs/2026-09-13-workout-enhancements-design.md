# Workout App Enhancements — Design Spec

Date: 2026-09-13

## Overview

Three enhancements to the Repwise Flutter app:
1. A new Weight Tracking screen, reachable from a persistent button on the Workout screen.
2. Minutes + Seconds side-by-side input for time-based exercises (replacing the single "Time (seconds)" field).
3. A pinned "Add Exercise" button in the exercise-selection bottom sheet, so it's always visible without scrolling.

## 1. Weight Tracking

### Data model

New file `lib/models/weight_entry.dart`:

```dart
class WeightEntry {
  final String id;
  final DateTime date;     // date-only (year/month/day), the day the weight applies to
  final double weight;     // stored in the app's current weightUnit (kg or lb) at time of entry
  final DateTime loggedAt; // full timestamp of when it was logged/last updated
}
```

- `fromJson`/`toJson` following the existing model conventions in `lib/models/workout.dart`.

### Provider changes (`RepwiseProvider`)

- `List<WeightEntry> _weightEntries` field, persisted via the existing `_serializeState`/`_applyStateFromMap` machinery under a new `weightEntries` key in the state JSON (same file, same `RepwiseStorage`).
- `List<WeightEntry> get weightEntries` — sorted by date ascending, unmodifiable.
- `void logWeight(double weight, {DateTime? date})`:
  - `date` defaults to today (date-only, time stripped).
  - If an entry already exists for that date, it is overwritten (weight + loggedAt updated) rather than duplicated — "latest value logged for a day wins."
  - Calls `notifyListeners()` and `_persist()`.
- `void deleteWeightEntry(String id)` (needed for correcting mistakes; minimal but useful).
- Existing `weightUnit` getter/setter is reused (no new unit concept needed).

### Screen: `lib/screens/weight_tracking_screen.dart`

A full-page `Scaffold` with an `AppBar` (title "Weight Tracker", back button), pushed via:
```dart
Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeightTrackingScreen()));
```

Contents (scrollable column):
1. **Log weight card** — `TextFormField` for weight (numeric, using current `weightUnit` as suffix label) + a date field (defaults to today, tappable to open `showDatePicker`, cannot be a future date) + "Save" button calling `provider.logWeight(...)`.
2. **Granularity selector** — `SegmentedButton<Granularity>` with Day / Week / Month.
   - Day: plot every daily entry as-is.
   - Week: bucket entries by ISO week; plot the **lowest** weight in each week.
   - Month: bucket entries by calendar month; plot the **lowest** weight in each month.
3. **Line chart** (via `fl_chart`'s `LineChart`) — x-axis = date (formatted per granularity: day → `d MMM`, week → `w/o d MMM`, month → `MMM yyyy`), y-axis = weight. Empty state message if no entries exist yet.
4. **Stats summary card** — current (latest) weight, change over last 7 days, change over last 30 days, all-time min/max. Computed client-side from `weightEntries`; hidden/simplified if insufficient data.

### Dependency

Add `fl_chart: ^0.68.0` (or latest compatible) to `pubspec.yaml`.

### Entry point on Workout screen

In `WorkoutScreen._buildHeader`, add an `IconButton` (`Icons.monitor_weight_outlined`) to the left of the existing timer button, always visible regardless of workout/timer state:
```dart
IconButton(
  tooltip: 'Track weight',
  onPressed: () => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const WeightTrackingScreen()),
  ),
  icon: const Icon(Icons.monitor_weight_outlined),
),
```

## 2. Minutes + Seconds Time Input

### Scope

Affects any exercise whose unit includes a time component: `ExerciseUnit.time`, `distanceTime`, `repsTime`, `weightTime`. Two call sites in the codebase build/edit sets with these fields using the same `_DraftSetEntry` pattern:
- `lib/screens/workout_screen.dart` (`showAddSetSheet`, used for logging live sets)
- `lib/screens/history_screen.dart` (editing a set from history)

Both must be updated so behavior/UI stays consistent.

### Changes

- `_DraftSetEntry` (private class in each file): replace the single `String time` field with `String minutes` and `String seconds`.
- Replace each `buildField(label: 'Time (seconds)', ...)` call with a new `buildTimeRow()` helper returning a `Row` with two `Expanded` `TextFormField`s side by side:
  - Left: hint/label `"Minutes"`, numeric integer keyboard, updates `draft.minutes`.
  - Right: hint/label `"Seconds"`, numeric integer keyboard, updates `draft.seconds`.
  - A small `SizedBox(width: 12)` gap between them, matching the existing weight/reps row spacing convention.
- Pre-population from an existing `WorkoutSetEntry.duration` (editing flow): `minutes = duration.inSeconds ~/ 60`, `seconds = duration.inSeconds % 60` (each converted to string, blank if zero-and-other-nonzero is fine — 0 renders as "0").
- Parsing on save: `parsePositiveDuration` logic is replaced with a combiner that reads both fields (each defaults to 0 if blank/invalid), computes `totalSeconds = minutes*60 + seconds`, and requires `totalSeconds > 0` (same validation error message as today, e.g. "Enter time for {exercise}.").
- Any draft-reset code (e.g., when switching exercises) that currently clears `draft.time = ''` is updated to clear both `draft.minutes = ''; draft.seconds = '';`.
- No changes to the persisted data model (`WorkoutSetEntry.duration` stays a single `Duration`, serialized as `durationSeconds` — fully backward compatible with existing saved data).

## 3. Pinned "Add Exercise" Button

### Scope

`WorkoutScreen.showStartExerciseSheet` — the modal bottom sheet for picking a muscle group and one or more exercises before starting/adding to a superset.

### Change

Currently the entire sheet (title, muscle-group dropdown, exercise checkboxes, button) is wrapped in one `SingleChildScrollView`, so the button can scroll out of view when a muscle group has many exercises.

New structure:
```dart
showModalBottomSheet<void>(
  isScrollControlled: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(..., bottom: viewInsets.bottom + 24),
    child: SizedBox(
      height: MediaQuery.of(sheetContext).size.height * 0.85,
      child: StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // fixed: title row, description text, muscle-group dropdown
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(children: [/* exercise checkboxes or empty-state text */]),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(/* Add Exercise — unchanged behavior */),
          ],
        ),
      ),
    ),
  ),
);
```
- The sheet gets a bounded height (85% of screen height) so `Expanded` + scroll works inside a bottom sheet.
- Only the exercise checkbox list scrolls; header, dropdown, and the button remain fixed/visible at all times.
- No behavioral change to selection logic, validation, or the add-exercise action itself.

## Testing / Verification

- `flutter analyze` and `flutter test` (existing test suite) after changes.
- Manual/logical check: existing saved workouts with `durationSeconds` still load and edit correctly (backward compatible).
- Manual check: weight entries persist across app restarts (same JSON file mechanism as everything else).

## Out of Scope

- Editing/deleting individual weight entries from a history list view (only the graph + summary + delete-by-id API; a full log/list UI is not required per the request, but the delete method is exposed for future use).
- Unit conversion of historical weight entries if the user changes kg/lb after logging (existing app-wide behavior for weight elsewhere is also not retroactive; consistent with current conventions).
