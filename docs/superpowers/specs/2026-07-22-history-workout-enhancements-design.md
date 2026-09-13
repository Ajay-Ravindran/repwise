# History & Workout Enhancements Design
**Date:** 2026-07-22  
**Project:** repwise (gym_log Flutter app)

---

## Overview

Six enhancements across the History screen and Workout screen to improve navigation, usability when filtering by muscle group, workout session management, and historical data editing.

---

## 1. Auto-Navigate to Most Recent Matching Day (History Screen)

**Trigger:** On two occasions the history screen should automatically jump to the most recent day that has a matching workout:

1. When the screen opens and a muscle group filter is already active (via auto-filter).
2. When the user selects a muscle group filter chip.

**Behaviour:**
- Call `provider.previousWorkoutDay(DateTime.now().add(Duration(days:1)), muscleGroupIds: _selectedMuscleGroupIds)` (effectively "last workout day up to and including today").
- If a day is found, set both `_selectedDay` and `_focusedDay` to that day in `setState`.
- If no day is found, leave the selection unchanged (no auto-navigation).
- When a filter chip is **deselected**, do not auto-navigate; the user stays on the current day.

**Entry points to update:**
- `initState` → existing `postFrameCallback` that applies auto-filter: extend to also call the navigate helper after setting `_selectedMuscleGroupIds`.
- `FilterChip.onSelected`: after updating `_selectedMuscleGroupIds` (when `selected == true`), call the helper.
- Auto-filter toggle in the overflow menu (enabling): also call the navigate helper after setting the filter.

---

## 2 & 3. Calendar Arrow Navigation Between Workout Days

**Problem:** The `TableCalendar` header left/right chevrons currently navigate months. When the user has a filter active (or even without filter), they want to jump to the previous or next day that has a logged workout.

**Solution:**

- Hide the default chevrons: `leftChevronVisible: false`, `rightChevronVisible: false` in `HeaderStyle`.
- Use `calendarBuilders.headerTitleBuilder` to render a custom `Row`:
  ```
  [ ← ]   Month Year   [ → ]
  ```
  The `←` and `→` are `IconButton`s with `Icons.chevron_left` / `Icons.chevron_right`.
- `←` calls `_navigateToPrevDay()`, `→` calls `_navigateToNextDay()`.
- Swipe-to-change-month (`onPageChanged`) remains unchanged and continues to update `_focusedDay`.

**Navigation logic:**

```
_navigateToPrevDay():
  day = provider.previousWorkoutDay(_selectedDay ?? _focusedDay, muscleGroupIds: _selectedMuscleGroupIds)
  if day != null: setState { _selectedDay = day; _focusedDay = day }

_navigateToNextDay():
  day = provider.nextWorkoutDay(_selectedDay ?? _focusedDay, muscleGroupIds: _selectedMuscleGroupIds)
  if day != null: setState { _selectedDay = day; _focusedDay = day }
```

- When `_selectedMuscleGroupIds` is non-empty, navigation jumps only to days matching the filter.
- When empty, navigation jumps to any day with a completed workout session.
- When no matching day exists in the given direction, the button does nothing (optionally show a brief snackbar "No more workouts").

---

## 4. Cancel Workout Session (Workout Screen)

**Trigger:** User starts a workout but hasn't added any sets (session exists but `hasLoggedSets == false`).

**Current state:** The "Finish Workout" button is disabled when `!hasLoggedSets`, but there is no way to discard the empty session.

**Change:**
- When `!hasLoggedSets`, replace the disabled "Finish Workout" button with an **"Cancel Workout"** `OutlinedButton` (icon: `Icons.cancel_outlined`).
- Tapping shows an `AlertDialog`:
  - Title: `"Cancel Workout?"`
  - Body: `"This workout has no sets logged. It will be discarded."`
  - Actions: `"Back"` (pop dialog) and `"Discard"` (confirm, calls `provider.finishWorkout()`).
- `provider.finishWorkout()` already handles sessions with no sets by discarding them without saving to history — no provider changes needed for this feature.
- When `hasLoggedSets`, show "Finish Workout" as today.

---

## 5. Exercise Detail Sheet with Add Set (History Screen)

**Trigger:** User taps on an `_ExerciseHistorySection` in the History screen.

**New widget:** `_HistoryExerciseDetailSheet` — a `showModalBottomSheet` that renders:

1. **Header row:** exercise name chip(s), `Chip` for muscle group name, `Chip` for "Superset" if applicable, close `IconButton`.
2. **Sets list:** Reuses existing `_WorkoutSetTile` widgets (same as current read-only view) — preserves PR icons, comment expand, set numbering.
3. **"Add Set" button** (`FilledButton.icon` with `Icons.add`): visible only if the muscle group and its exercises still exist in the library.
   - If the muscle group has been deleted, show: `"The muscle group for this exercise has been removed from the library. Sets cannot be added."` instead of the button.

**Add Set flow (new static method `showAddSetToHistorySheet`):**
- Mirrors `WorkoutScreen.showAddSetSheet` in structure: same draft-entry model, same per-exercise metric fields, same validation.
- Key difference: on save, calls `provider.addSetToCompletedSession(sessionId: ..., exerciseLogId: ..., entries: ...)` instead of `provider.addSetToExercise(...)`.
- Pre-populates from the last set of the exercise (same as active workout behaviour).
- On success, closes the sheet and shows a snackbar: `"Set added"`.

**Making `_ExerciseHistorySection` tappable:**
- Wrap with `InkWell` / `GestureDetector` that opens the detail sheet.
- Pass `sessionId` (already available on `_ExerciseHistorySection`) through to the sheet.

---

## 6. Selected Muscle Groups First in Filter Bar (History Screen)

**Current behaviour:** `_getAllWorkoutMuscleGroups` returns all muscle groups sorted alphabetically.

**New behaviour:** Split into two groups, both sorted alphabetically, then concatenate:
1. Selected muscle groups (those in `_selectedMuscleGroupIds`) — alphabetical.
2. Unselected muscle groups — alphabetical.

**Implementation:** Modify `_getAllWorkoutMuscleGroups` to accept `selectedIds` (or read from `_selectedMuscleGroupIds` directly since it's on the state object), split, sort each half, and return the combined list.

Since `_selectedMuscleGroupIds` is part of widget state, every `setState` call from chip selection triggers a rebuild with the new ordering — no extra plumbing needed.

---

## Provider Changes

### `nextWorkoutDay(DateTime after, {Set<String> muscleGroupIds = const {}})`
Scans `_completedSessions` for the earliest session date strictly after `after` that has at least one exercise with a set matching `muscleGroupIds` (or any exercise if `muscleGroupIds` is empty).  
Returns `DateTime?` (date-only, no time component).

### `previousWorkoutDay(DateTime before, {Set<String> muscleGroupIds = const {}})`
Same but returns the latest session date strictly before `before`.  
`_completedSessions` is stored newest-first, so `previousWorkoutDay` can return on the first match.

### `addSetToCompletedSession({required String sessionId, required String exerciseLogId, required List<WorkoutSetEntry> entries})`
Mirrors `addSetToExercise` but targets a completed session:
- Finds session by `sessionId` in `_completedSessions`.
- Finds `WorkoutExerciseLog` by `exerciseLogId`.
- Validates entries against the exercise's muscle group (same logic as active-session version).
- Creates a `WorkoutSet` with a new UUID and `DateTime.now()`.
- Appends to `exercise.sets`.
- Calls `notifyListeners()` and `_persist()`.
- Returns `bool` success.

---

## Affected Files

| File | Changes |
|------|---------|
| `lib/providers/repwise_provider.dart` | Add `nextWorkoutDay`, `previousWorkoutDay`, `addSetToCompletedSession` |
| `lib/screens/history_screen.dart` | Features 1, 2, 3, 5, 6: navigation helpers, custom header, chip ordering, detail sheet, add-set sheet |
| `lib/screens/workout_screen.dart` | Feature 4: cancel workout button + dialog |

No new files required; no model changes required.

---

## Edge Cases

- **No workouts in navigation direction:** Arrow button does nothing silently (or optional snackbar).
- **All muscle group exercises deleted:** Add Set button hidden in detail sheet with explanatory message.
- **Session/exercise deleted mid-flow:** `addSetToCompletedSession` returns `false`, sheet shows an error snackbar.
- **Auto-filter enabled but no active workout:** No muscle group is auto-selected, no auto-navigation.
- **Multiple muscle groups selected:** Navigation finds days where *any* of the selected muscle groups was worked.
