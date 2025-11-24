import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/exercise.dart';
import '../models/muscle_group.dart';
import '../models/workout.dart';
import '../utils/gym_log_storage.dart';

class GymLogProvider extends ChangeNotifier {
  GymLogProvider({GymLogStorage? storage})
    : _storage = storage ?? const GymLogStorage();

  final GymLogStorage _storage;
  final Uuid _uuid = const Uuid();
  final List<MuscleGroup> _muscleGroups = <MuscleGroup>[];
  final List<WorkoutSession> _completedSessions = <WorkoutSession>[];
  WorkoutSession? _activeSession;
  Timer? _timer;
  Duration? _timerTotalDuration;
  Duration? _timerRemaining;
  bool _timerRunning = false;
  bool _timerSoundEnabled = true;
  bool _timerVibrationEnabled = true;
  bool _timerCollapsed = false;
  int _timerCompletionSignalId = 0;
  bool _initialized = false;

  List<MuscleGroup> get muscleGroups =>
      List<MuscleGroup>.unmodifiable(_muscleGroups);
  WorkoutSession? get activeSession => _activeSession;
  List<WorkoutExerciseLog> get activeExercises => _activeSession == null
      ? const <WorkoutExerciseLog>[]
      : List<WorkoutExerciseLog>.unmodifiable(_activeSession!.exercises);
  WorkoutExerciseLog? get activeExercise {
    final session = _activeSession;
    if (session == null) {
      return null;
    }
    for (final exercise in session.exercises.reversed) {
      if (!exercise.isComplete) {
        return exercise;
      }
    }
    return null;
  }

  List<WorkoutSession> get completedSessions =>
      List<WorkoutSession>.unmodifiable(_completedSessions);
  Duration? get timerTotalDuration => _timerTotalDuration;
  Duration? get timerRemaining => _timerRemaining;
  Duration? get timerElapsed =>
      _timerTotalDuration == null || _timerRemaining == null
      ? null
      : _timerTotalDuration! - _timerRemaining!;
  bool get isTimerRunning => _timerRunning;
  bool get isTimerActive => _timerTotalDuration != null;
  bool get timerCollapsed => _timerCollapsed;
  bool get timerSoundEnabled => _timerSoundEnabled;
  bool get timerVibrationEnabled => _timerVibrationEnabled;
  int get timerCompletionId => _timerCompletionSignalId;
  bool get isTimerComplete =>
      isTimerActive &&
      !_timerRunning &&
      (_timerRemaining ?? Duration.zero).inSeconds == 0;
  bool get isInitialized => _initialized;

  Map<DateTime, List<WorkoutSession>> get completedSessionsByDate {
    final Map<DateTime, List<WorkoutSession>> grouped =
        <DateTime, List<WorkoutSession>>{};
    for (final session in _completedSessions) {
      final dateOnly = _dateOnly(session.startedAt);
      grouped.putIfAbsent(dateOnly, () => <WorkoutSession>[]).add(session);
    }
    return grouped;
  }

  List<WorkoutSession> sessionsForDay(DateTime day) {
    final dateOnly = _dateOnly(day);
    return List<WorkoutSession>.unmodifiable(
      completedSessionsByDate[dateOnly] ?? const <WorkoutSession>[],
    );
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final state = await _storage.readState();
    if (state != null) {
      _applyStateFromMap(state);
    } else {
      _resetTimerState();
    }
    _initialized = true;
    notifyListeners();
  }

  Future<File?> createExportFile() async {
    if (!_initialized) {
      await initialize();
    }
    return _storage.createExportFile(_serializeState());
  }

  Future<bool> importFromFile(File file) async {
    try {
      final contents = await file.readAsString();
      return importFromJson(contents);
    } catch (_) {
      return false;
    }
  }

  Future<bool> importFromJson(String jsonSource) async {
    try {
      final dynamic decoded = jsonDecode(jsonSource);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }
      _applyStateFromMap(decoded);
      _initialized = true;
      notifyListeners();
      await _persist();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _applyStateFromMap(Map<String, dynamic> map) {
    _resetTimerState();

    _muscleGroups
      ..clear()
      ..addAll(_decodeMuscleGroups(map['muscleGroups']));

    _completedSessions
      ..clear()
      ..addAll(_decodeSessions(map['completedSessions']));

    final active = map['activeSession'];
    if (active is Map<String, dynamic>) {
      _activeSession = WorkoutSession.fromJson(active);
    } else {
      _activeSession = null;
    }

    final settings = map['settings'];
    if (settings is Map<String, dynamic>) {
      _timerSoundEnabled = settings['timerSoundEnabled'] as bool? ?? true;
      _timerVibrationEnabled =
          settings['timerVibrationEnabled'] as bool? ?? true;
    }
  }

  List<MuscleGroup> _decodeMuscleGroups(dynamic value) {
    if (value is! List) {
      return <MuscleGroup>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(MuscleGroup.fromJson)
        .toList();
  }

  List<WorkoutSession> _decodeSessions(dynamic value) {
    if (value is! List) {
      return <WorkoutSession>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(WorkoutSession.fromJson)
        .toList();
  }

  void _resetTimerState() {
    _timer?.cancel();
    _timer = null;
    _timerRunning = false;
    _timerTotalDuration = null;
    _timerRemaining = null;
    _timerCollapsed = false;
    _timerCompletionSignalId = 0;
  }

  Map<String, dynamic> _serializeState() {
    return <String, dynamic>{
      'muscleGroups': _muscleGroups.map((group) => group.toJson()).toList(),
      'completedSessions': _completedSessions
          .map((session) => session.toJson())
          .toList(),
      'activeSession': _activeSession?.toJson(),
      'settings': <String, dynamic>{
        'timerSoundEnabled': _timerSoundEnabled,
        'timerVibrationEnabled': _timerVibrationEnabled,
      },
    };
  }

  Future<void> _persist() async {
    if (!_initialized) {
      return;
    }
    await _storage.writeState(_serializeState());
  }

  MuscleGroup? muscleGroupById(String id) {
    for (final group in _muscleGroups) {
      if (group.id == id) {
        return group;
      }
    }
    return null;
  }

  void addMuscleGroup(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final exists = _muscleGroups.any(
      (group) => group.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) {
      return;
    }
    _muscleGroups.add(MuscleGroup(id: _uuid.v4(), name: trimmed));
    notifyListeners();
    unawaited(_persist());
  }

  void updateMuscleGroup(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final index = _muscleGroups.indexWhere((group) => group.id == id);
    if (index == -1) {
      return;
    }
    final exists = _muscleGroups.any(
      (group) =>
          group.id != id && group.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) {
      return;
    }
    final current = _muscleGroups[index];
    _muscleGroups[index] = current.copyWith(name: trimmed);
    notifyListeners();
    unawaited(_persist());
  }

  void addExercise(String muscleGroupId, String name, ExerciseUnit unit) {
    final groupIndex = _muscleGroups.indexWhere(
      (group) => group.id == muscleGroupId,
    );
    if (groupIndex == -1) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final group = _muscleGroups[groupIndex];
    final exists = group.exercises.any(
      (exercise) => exercise.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) {
      return;
    }
    group.exercises.add(Exercise(id: _uuid.v4(), name: trimmed, unit: unit));
    notifyListeners();
    unawaited(_persist());
  }

  void updateExercise({
    required String muscleGroupId,
    required String exerciseId,
    required String name,
    required ExerciseUnit unit,
  }) {
    final groupIndex = _muscleGroups.indexWhere(
      (group) => group.id == muscleGroupId,
    );
    if (groupIndex == -1) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final group = _muscleGroups[groupIndex];
    final exerciseIndex = group.exercises.indexWhere(
      (exercise) => exercise.id == exerciseId,
    );
    if (exerciseIndex == -1) {
      return;
    }
    final exists = group.exercises.any(
      (exercise) =>
          exercise.id != exerciseId &&
          exercise.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) {
      return;
    }
    group.exercises[exerciseIndex] = group.exercises[exerciseIndex].copyWith(
      name: trimmed,
      unit: unit,
    );
    notifyListeners();
    unawaited(_persist());
  }

  void startTimer({
    required Duration duration,
    required bool enableSound,
    required bool enableVibration,
  }) {
    if (duration.inSeconds <= 0) {
      return;
    }
    _timer?.cancel();
    _timerTotalDuration = duration;
    _timerRemaining = duration;
    _timerRunning = true;
    _timerSoundEnabled = enableSound;
    _timerVibrationEnabled = enableVibration;
    _timerCollapsed = false;
    _timer = Timer.periodic(const Duration(seconds: 1), _handleTimerTick);
    notifyListeners();
  }

  void pauseTimer() {
    if (!_timerRunning || _timerRemaining == null) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _timerRunning = false;
    notifyListeners();
  }

  void resumeTimer() {
    if (_timerRunning ||
        _timerRemaining == null ||
        _timerRemaining!.inSeconds <= 0) {
      return;
    }
    _timerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), _handleTimerTick);
    notifyListeners();
  }

  void restartTimer() {
    if (_timerTotalDuration == null) {
      return;
    }
    startTimer(
      duration: _timerTotalDuration!,
      enableSound: _timerSoundEnabled,
      enableVibration: _timerVibrationEnabled,
    );
  }

  void dismissTimer() {
    if (_timerTotalDuration == null && _timerRemaining == null) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _timerRunning = false;
    _timerTotalDuration = null;
    _timerRemaining = null;
    _timerCollapsed = false;
    notifyListeners();
  }

  void setTimerCollapsed(bool value) {
    if (_timerCollapsed == value || !isTimerActive) {
      return;
    }
    _timerCollapsed = value;
    notifyListeners();
  }

  void updateTimerPreferences({bool? soundEnabled, bool? vibrationEnabled}) {
    var changed = false;
    if (soundEnabled != null && soundEnabled != _timerSoundEnabled) {
      _timerSoundEnabled = soundEnabled;
      changed = true;
    }
    if (vibrationEnabled != null &&
        vibrationEnabled != _timerVibrationEnabled) {
      _timerVibrationEnabled = vibrationEnabled;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(_persist());
    }
  }

  void _handleTimerTick(Timer timer) {
    if (_timerRemaining == null) {
      timer.cancel();
      return;
    }
    final next = _timerRemaining! - const Duration(seconds: 1);
    if (next.inSeconds <= 0) {
      timer.cancel();
      _timer = null;
      _timerRemaining = Duration.zero;
      _timerRunning = false;
      _timerCompletionSignalId++;
      notifyListeners();
    } else {
      _timerRemaining = next;
      notifyListeners();
    }
  }

  void startWorkout() {
    if (_activeSession != null) {
      return;
    }
    _activeSession = WorkoutSession(id: _uuid.v4(), startedAt: DateTime.now());
    notifyListeners();
    unawaited(_persist());
  }

  void finishWorkout() {
    if (_activeSession == null) {
      return;
    }
    final session = _activeSession!;
    session.exercises.removeWhere((exercise) => exercise.sets.isEmpty);
    if (session.exercises.isEmpty) {
      _activeSession = null;
      notifyListeners();
      unawaited(_persist());
      return;
    }
    final completionTime = DateTime.now();
    for (final exercise in session.exercises) {
      exercise.finishedAt ??= completionTime;
    }
    _completedSessions.insert(0, session);
    _activeSession = null;
    notifyListeners();
    unawaited(_persist());
  }

  WorkoutExerciseLog? startExercise({
    required String muscleGroupId,
    required List<String> exerciseIds,
  }) {
    final session = _activeSession;
    if (session == null) {
      return null;
    }
    if (activeExercise != null) {
      return null;
    }
    if (!_muscleGroups.any((group) => group.id == muscleGroupId)) {
      return null;
    }
    final uniqueIds = Set<String>.from(exerciseIds).toList();
    if (uniqueIds.isEmpty) {
      return null;
    }
    final group = muscleGroupById(muscleGroupId);
    if (group == null) {
      return null;
    }
    final allowed = group.exercises.map((exercise) => exercise.id).toSet();
    if (!uniqueIds.every(allowed.contains)) {
      return null;
    }
    final log = WorkoutExerciseLog(
      id: _uuid.v4(),
      muscleGroupId: muscleGroupId,
      exerciseIds: uniqueIds,
      startedAt: DateTime.now(),
    );
    session.exercises.add(log);
    notifyListeners();
    unawaited(_persist());
    return log;
  }

  bool cancelExercise(String exerciseLogId) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final index = session.exercises.indexWhere(
      (exercise) => exercise.id == exerciseLogId,
    );
    if (index == -1) {
      return false;
    }
    final exercise = session.exercises[index];
    if (exercise.hasSets) {
      return false;
    }
    session.exercises.removeAt(index);
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool completeExercise(String exerciseLogId) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final exercise = _exerciseById(session, exerciseLogId);
    if (exercise == null) {
      return false;
    }
    if (!exercise.hasSets) {
      return false;
    }
    exercise.finishedAt = DateTime.now();
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool reopenExercise(String exerciseLogId) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final exercise = _exerciseById(session, exerciseLogId);
    if (exercise == null) {
      return false;
    }
    final currentActive = activeExercise;
    if (currentActive != null && currentActive.id != exerciseLogId) {
      return false;
    }
    exercise.finishedAt = null;
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool addSetToExercise({
    required String exerciseLogId,
    required List<WorkoutSetEntry> entries,
  }) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final exercise = _exerciseById(session, exerciseLogId);
    if (exercise == null) {
      return false;
    }
    final group = muscleGroupById(exercise.muscleGroupId);
    if (group == null) {
      return false;
    }
    final allowedIds = group.exercises.map((exercise) => exercise.id).toSet();
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
    exercise.finishedAt = null;
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool updateSetInExercise({
    required String exerciseLogId,
    required String setId,
    required List<WorkoutSetEntry> entries,
  }) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final exercise = _exerciseById(session, exerciseLogId);
    if (exercise == null) {
      return false;
    }
    final group = muscleGroupById(exercise.muscleGroupId);
    if (group == null) {
      return false;
    }
    final allowedIds = group.exercises.map((exercise) => exercise.id).toSet();
    final validEntries = entries
        .where(
          (entry) => entry.hasMetrics && allowedIds.contains(entry.exerciseId),
        )
        .toList(growable: false);
    if (validEntries.isEmpty) {
      return false;
    }
    final setIndex = exercise.sets.indexWhere((set) => set.id == setId);
    if (setIndex == -1) {
      return false;
    }
    final existing = exercise.sets[setIndex];
    exercise.sets[setIndex] = WorkoutSet(
      id: existing.id,
      muscleGroupId: exercise.muscleGroupId,
      entries: validEntries,
      timestamp: existing.timestamp,
    );
    exercise.finishedAt = null;
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool removeSetFromExercise({
    required String exerciseLogId,
    required String setId,
  }) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final exercise = _exerciseById(session, exerciseLogId);
    if (exercise == null) {
      return false;
    }
    final index = exercise.sets.indexWhere((set) => set.id == setId);
    if (index == -1) {
      return false;
    }
    exercise.sets.removeAt(index);
    if (exercise.sets.isEmpty) {
      exercise.finishedAt = null;
    }
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool reorderSetsInExercise({
    required String exerciseLogId,
    required int oldIndex,
    required int newIndex,
  }) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final exercise = _exerciseById(session, exerciseLogId);
    if (exercise == null) {
      return false;
    }
    if (oldIndex < 0 || oldIndex >= exercise.sets.length) {
      return false;
    }
    if (newIndex < 0 || newIndex > exercise.sets.length) {
      return false;
    }
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    final moved = exercise.sets.removeAt(oldIndex);
    exercise.sets.insert(targetIndex, moved);
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool removeActiveExercise(String exerciseLogId) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final index = session.exercises.indexWhere(
      (exercise) => exercise.id == exerciseLogId,
    );
    if (index == -1) {
      return false;
    }
    session.exercises.removeAt(index);
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool removeCompletedSet({
    required String sessionId,
    required String exerciseLogId,
    required String setId,
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
    final setIndex = exercise.sets.indexWhere((set) => set.id == setId);
    if (setIndex == -1) {
      return false;
    }
    exercise.sets.removeAt(setIndex);
    if (exercise.sets.isEmpty) {
      session.exercises.removeWhere((element) => element.id == exerciseLogId);
    }
    if (session.exercises.isEmpty) {
      _completedSessions.removeAt(sessionIndex);
    }
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  Exercise? exerciseById(String id) {
    for (final group in _muscleGroups) {
      for (final exercise in group.exercises) {
        if (exercise.id == id) {
          return exercise;
        }
      }
    }
    return null;
  }

  WorkoutExerciseLog? _exerciseById(WorkoutSession session, String exerciseId) {
    for (final exercise in session.exercises) {
      if (exercise.id == exerciseId) {
        return exercise;
      }
    }
    return null;
  }

  DateTime _dateOnly(DateTime dateTime) =>
      DateTime(dateTime.year, dateTime.month, dateTime.day);

  /// Check if a set entry is a personal record.
  /// Only checks for single-exercise sets (not supersets).
  /// For multi-unit exercises, returns true if ANY unit is a PR.
  /// Ignores half reps in PR calculations.
  /// Only marks the first set with the highest value as a PR.
  bool isPersonalRecord(
    WorkoutSetEntry entry,
    WorkoutSet currentSet, {
    WorkoutSession? excludeSession,
  }) {
    // Only track PRs for single-exercise sets
    if (currentSet.entries.length > 1) {
      return false;
    }

    final exercise = exerciseById(entry.exerciseId);
    if (exercise == null) {
      return false;
    }

    // Gather all entries for this exercise (including current session)
    final allEntries = <({WorkoutSet set, WorkoutSetEntry entry})>[];

    // Check completed sessions
    for (final session in _completedSessions) {
      if (excludeSession != null && session.id == excludeSession.id) {
        continue;
      }
      for (final exerciseLog in session.exercises) {
        for (final set in exerciseLog.sets) {
          // Only compare single-exercise sets
          if (set.entries.length == 1) {
            for (final prevEntry in set.entries) {
              if (prevEntry.exerciseId == entry.exerciseId) {
                allEntries.add((set: set, entry: prevEntry));
              }
            }
          }
        }
      }
    }

    // Check active session if not excluded
    if (_activeSession != null &&
        (excludeSession == null || _activeSession!.id != excludeSession.id)) {
      for (final exerciseLog in _activeSession!.exercises) {
        for (final set in exerciseLog.sets) {
          // Only compare single-exercise sets, and exclude the current set
          if (set.entries.length == 1 && set.id != currentSet.id) {
            for (final prevEntry in set.entries) {
              if (prevEntry.exerciseId == entry.exerciseId) {
                allEntries.add((set: set, entry: prevEntry));
              }
            }
          }
        }
      }
    }

    // If no other entries, this is the first time doing this exercise
    if (allEntries.isEmpty) {
      return true; // First time is always a PR
    }

    // Check based on exercise unit type
    switch (exercise.unit) {
      case ExerciseUnit.weightReps:
        // PR if either weight OR reps is strictly higher (ignoring half reps)
        final currentWeight = entry.weight ?? 0;
        final currentReps = entry.reps ?? 0;

        var maxWeight = 0.0;
        var maxReps = 0;

        for (final record in allEntries) {
          final prevWeight = record.entry.weight ?? 0;
          final prevReps = record.entry.reps ?? 0;
          if (prevWeight > maxWeight) maxWeight = prevWeight;
          if (prevReps > maxReps) maxReps = prevReps;
        }

        // Check if current set has higher weight or reps than all previous
        final hasWeightPR = currentWeight > maxWeight;
        final hasRepsPR = currentReps > maxReps;

        if (!hasWeightPR && !hasRepsPR) {
          return false;
        }

        // If it has a PR, check if it's the first set with this value in the active session
        if (hasWeightPR && currentWeight >= maxWeight) {
          // Check if any earlier set in active session has same weight
          for (final record in allEntries) {
            if (record.set.id == currentSet.id) break;
            if (_activeSession != null &&
                _isSetInSession(record.set, _activeSession!)) {
              final prevWeight = record.entry.weight ?? 0;
              if (prevWeight == currentWeight) {
                return false; // Earlier set has same weight
              }
            }
          }
        }

        if (hasRepsPR && currentReps >= maxReps) {
          // Check if any earlier set in active session has same reps
          for (final record in allEntries) {
            if (record.set.id == currentSet.id) break;
            if (_activeSession != null &&
                _isSetInSession(record.set, _activeSession!)) {
              final prevReps = record.entry.reps ?? 0;
              if (prevReps == currentReps) {
                return false; // Earlier set has same reps
              }
            }
          }
        }

        return true;

      case ExerciseUnit.reps:
        // PR if reps is strictly higher (ignoring half reps)
        final currentReps = entry.reps ?? 0;
        var maxReps = 0;

        for (final record in allEntries) {
          final prevReps = record.entry.reps ?? 0;
          if (prevReps > maxReps) maxReps = prevReps;
        }

        if (currentReps <= maxReps) {
          return false;
        }

        // Check if any earlier set in active session has same reps
        for (final record in allEntries) {
          if (record.set.id == currentSet.id) break;
          if (_activeSession != null &&
              _isSetInSession(record.set, _activeSession!)) {
            final prevReps = record.entry.reps ?? 0;
            if (prevReps == currentReps) {
              return false;
            }
          }
        }

        return true;

      case ExerciseUnit.time:
        // PR if time is strictly higher
        final currentSeconds = entry.duration?.inSeconds ?? 0;
        var maxSeconds = 0;

        for (final record in allEntries) {
          final prevSeconds = record.entry.duration?.inSeconds ?? 0;
          if (prevSeconds > maxSeconds) maxSeconds = prevSeconds;
        }

        if (currentSeconds <= maxSeconds) {
          return false;
        }

        // Check if any earlier set in active session has same time
        for (final record in allEntries) {
          if (record.set.id == currentSet.id) break;
          if (_activeSession != null &&
              _isSetInSession(record.set, _activeSession!)) {
            final prevSeconds = record.entry.duration?.inSeconds ?? 0;
            if (prevSeconds == currentSeconds) {
              return false;
            }
          }
        }

        return true;

      case ExerciseUnit.distanceTime:
        // PR if either distance OR time is strictly higher
        final currentDistance = entry.distance ?? 0;
        final currentSeconds = entry.duration?.inSeconds ?? 0;

        var maxDistance = 0.0;
        var maxSeconds = 0;

        for (final record in allEntries) {
          final prevDistance = record.entry.distance ?? 0;
          final prevSeconds = record.entry.duration?.inSeconds ?? 0;
          if (prevDistance > maxDistance) maxDistance = prevDistance;
          if (prevSeconds > maxSeconds) maxSeconds = prevSeconds;
        }

        final hasDistancePR = currentDistance > maxDistance;
        final hasTimePR = currentSeconds > maxSeconds;

        if (!hasDistancePR && !hasTimePR) {
          return false;
        }

        // Check if any earlier set in active session has same values
        if (hasDistancePR) {
          for (final record in allEntries) {
            if (record.set.id == currentSet.id) break;
            if (_activeSession != null &&
                _isSetInSession(record.set, _activeSession!)) {
              final prevDistance = record.entry.distance ?? 0;
              if (prevDistance == currentDistance) {
                return false;
              }
            }
          }
        }

        if (hasTimePR) {
          for (final record in allEntries) {
            if (record.set.id == currentSet.id) break;
            if (_activeSession != null &&
                _isSetInSession(record.set, _activeSession!)) {
              final prevSeconds = record.entry.duration?.inSeconds ?? 0;
              if (prevSeconds == currentSeconds) {
                return false;
              }
            }
          }
        }

        return true;

      case ExerciseUnit.repsTime:
        // PR if either reps OR time is strictly higher (ignoring half reps)
        final currentReps = entry.reps ?? 0;
        final currentSeconds = entry.duration?.inSeconds ?? 0;

        var maxReps = 0;
        var maxSeconds = 0;

        for (final record in allEntries) {
          final prevReps = record.entry.reps ?? 0;
          final prevSeconds = record.entry.duration?.inSeconds ?? 0;
          if (prevReps > maxReps) maxReps = prevReps;
          if (prevSeconds > maxSeconds) maxSeconds = prevSeconds;
        }

        final hasRepsPR = currentReps > maxReps;
        final hasTimePR = currentSeconds > maxSeconds;

        if (!hasRepsPR && !hasTimePR) {
          return false;
        }

        // Check if any earlier set in active session has same values
        if (hasRepsPR) {
          for (final record in allEntries) {
            if (record.set.id == currentSet.id) break;
            if (_activeSession != null &&
                _isSetInSession(record.set, _activeSession!)) {
              final prevReps = record.entry.reps ?? 0;
              if (prevReps == currentReps) {
                return false;
              }
            }
          }
        }

        if (hasTimePR) {
          for (final record in allEntries) {
            if (record.set.id == currentSet.id) break;
            if (_activeSession != null &&
                _isSetInSession(record.set, _activeSession!)) {
              final prevSeconds = record.entry.duration?.inSeconds ?? 0;
              if (prevSeconds == currentSeconds) {
                return false;
              }
            }
          }
        }

        return true;

      case ExerciseUnit.distance:
        // PR if distance is strictly higher
        final currentDistance = entry.distance ?? 0;
        var maxDistance = 0.0;

        for (final record in allEntries) {
          final prevDistance = record.entry.distance ?? 0;
          if (prevDistance > maxDistance) maxDistance = prevDistance;
        }

        if (currentDistance <= maxDistance) {
          return false;
        }

        // Check if any earlier set in active session has same distance
        for (final record in allEntries) {
          if (record.set.id == currentSet.id) break;
          if (_activeSession != null &&
              _isSetInSession(record.set, _activeSession!)) {
            final prevDistance = record.entry.distance ?? 0;
            if (prevDistance == currentDistance) {
              return false;
            }
          }
        }

        return true;
    }
  }

  /// Helper method to check if a set belongs to a session
  bool _isSetInSession(WorkoutSet set, WorkoutSession session) {
    for (final exerciseLog in session.exercises) {
      for (final s in exerciseLog.sets) {
        if (s.id == set.id) {
          return true;
        }
      }
    }
    return false;
  }

  /// Get current PR sets for a specific exercise.
  /// Returns set IDs that hold current PRs.
  Set<String> getCurrentPRs(String exerciseId) {
    final exercise = exerciseById(exerciseId);
    if (exercise == null) {
      return <String>{};
    }

    final prSetIds = <String>{};

    // Collect all single-exercise sets for this exercise from all sessions
    final allSets = <({WorkoutSet set, WorkoutSetEntry entry})>[];

    // Collect from completed sessions
    for (final session in _completedSessions) {
      for (final exerciseLog in session.exercises) {
        for (final set in exerciseLog.sets) {
          if (set.entries.length == 1) {
            for (final entry in set.entries) {
              if (entry.exerciseId == exerciseId) {
                allSets.add((set: set, entry: entry));
              }
            }
          }
        }
      }
    }

    // Collect from active session
    if (_activeSession != null) {
      for (final exerciseLog in _activeSession!.exercises) {
        for (final set in exerciseLog.sets) {
          if (set.entries.length == 1) {
            for (final entry in set.entries) {
              if (entry.exerciseId == exerciseId) {
                allSets.add((set: set, entry: entry));
              }
            }
          }
        }
      }
    }

    if (allSets.isEmpty) {
      return prSetIds;
    }

    // Find max values for each metric
    switch (exercise.unit) {
      case ExerciseUnit.weightReps:
        var maxWeight = 0.0;
        var maxReps = 0;

        for (final record in allSets) {
          final weight = record.entry.weight ?? 0;
          final reps = record.entry.reps ?? 0;
          if (weight > maxWeight) maxWeight = weight;
          if (reps > maxReps) maxReps = reps;
        }

        // Find earliest set with max weight (if there are ties, pick the one with most reps)
        String? maxWeightSetId;
        var maxWeightWithMostReps = 0;
        for (final record in allSets) {
          final weight = record.entry.weight ?? 0;
          final reps = record.entry.reps ?? 0;
          if (weight == maxWeight) {
            if (maxWeightSetId == null || reps > maxWeightWithMostReps) {
              maxWeightSetId = record.set.id;
              maxWeightWithMostReps = reps;
            }
          }
        }

        // Find earliest set with max reps (if there are ties, pick the one with most weight)
        String? maxRepsSetId;
        var maxRepsWithMostWeight = 0.0;
        for (final record in allSets) {
          final weight = record.entry.weight ?? 0;
          final reps = record.entry.reps ?? 0;
          if (reps == maxReps) {
            if (maxRepsSetId == null || weight > maxRepsWithMostWeight) {
              maxRepsSetId = record.set.id;
              maxRepsWithMostWeight = weight;
            }
          }
        }

        if (maxWeightSetId != null) prSetIds.add(maxWeightSetId);
        if (maxRepsSetId != null && maxRepsSetId != maxWeightSetId) {
          prSetIds.add(maxRepsSetId);
        }
        break;

      case ExerciseUnit.reps:
        var maxReps = 0;

        for (final record in allSets) {
          final reps = record.entry.reps ?? 0;
          if (reps > maxReps) maxReps = reps;
        }

        // Find earliest set with max reps
        for (final record in allSets) {
          final reps = record.entry.reps ?? 0;
          if (reps == maxReps) {
            prSetIds.add(record.set.id);
            break;
          }
        }
        break;

      case ExerciseUnit.time:
        var maxSeconds = 0;

        for (final record in allSets) {
          final seconds = record.entry.duration?.inSeconds ?? 0;
          if (seconds > maxSeconds) maxSeconds = seconds;
        }

        // Find earliest set with max time
        for (final record in allSets) {
          final seconds = record.entry.duration?.inSeconds ?? 0;
          if (seconds == maxSeconds) {
            prSetIds.add(record.set.id);
            break;
          }
        }
        break;

      case ExerciseUnit.distanceTime:
        var maxDistance = 0.0;
        var maxSeconds = 0;

        for (final record in allSets) {
          final distance = record.entry.distance ?? 0;
          final seconds = record.entry.duration?.inSeconds ?? 0;
          if (distance > maxDistance) maxDistance = distance;
          if (seconds > maxSeconds) maxSeconds = seconds;
        }

        // Find earliest set with max distance
        String? maxDistanceSetId;
        for (final record in allSets) {
          final distance = record.entry.distance ?? 0;
          if (distance == maxDistance) {
            maxDistanceSetId = record.set.id;
            break;
          }
        }

        // Find earliest set with max time
        String? maxSecondsSetId;
        for (final record in allSets) {
          final seconds = record.entry.duration?.inSeconds ?? 0;
          if (seconds == maxSeconds) {
            maxSecondsSetId = record.set.id;
            break;
          }
        }

        if (maxDistanceSetId != null) prSetIds.add(maxDistanceSetId);
        if (maxSecondsSetId != null && maxSecondsSetId != maxDistanceSetId) {
          prSetIds.add(maxSecondsSetId);
        }
        break;

      case ExerciseUnit.repsTime:
        var maxReps = 0;
        var maxSeconds = 0;

        for (final record in allSets) {
          final reps = record.entry.reps ?? 0;
          final seconds = record.entry.duration?.inSeconds ?? 0;
          if (reps > maxReps) maxReps = reps;
          if (seconds > maxSeconds) maxSeconds = seconds;
        }

        // Find earliest set with max reps
        String? maxRepsSetId;
        for (final record in allSets) {
          final reps = record.entry.reps ?? 0;
          if (reps == maxReps) {
            maxRepsSetId = record.set.id;
            break;
          }
        }

        // Find earliest set with max time
        String? maxSecondsSetId;
        for (final record in allSets) {
          final seconds = record.entry.duration?.inSeconds ?? 0;
          if (seconds == maxSeconds) {
            maxSecondsSetId = record.set.id;
            break;
          }
        }

        if (maxRepsSetId != null) prSetIds.add(maxRepsSetId);
        if (maxSecondsSetId != null && maxSecondsSetId != maxRepsSetId) {
          prSetIds.add(maxSecondsSetId);
        }
        break;

      case ExerciseUnit.distance:
        var maxDistance = 0.0;

        for (final record in allSets) {
          final distance = record.entry.distance ?? 0;
          if (distance > maxDistance) maxDistance = distance;
        }

        // Find earliest set with max distance
        for (final record in allSets) {
          final distance = record.entry.distance ?? 0;
          if (distance == maxDistance) {
            prSetIds.add(record.set.id);
            break;
          }
        }
        break;
    }

    return prSetIds;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
