import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/exercise.dart';
import '../models/muscle_group.dart';
import '../models/workout.dart';
import '../utils/repwise_storage.dart';

class RepwiseProvider extends ChangeNotifier {
  RepwiseProvider({RepwiseStorage? storage})
    : _storage = storage ?? const RepwiseStorage();

  final RepwiseStorage _storage;
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

  // App Settings
  String _weightUnit = 'kg'; // 'kg' or 'lb'
  String _distanceUnit = 'km'; // 'km' or 'mi'
  bool _halfRepsEnabled = false;
  bool _commentsEnabled = true;
  bool _autoFinishWorkoutEnabled = false;
  int _autoFinishWorkoutHours = 4;
  bool _autoFilterHistoryEnabled = false;

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

  // Settings getters
  String get weightUnit => _weightUnit;
  String get distanceUnit => _distanceUnit;
  bool get halfRepsEnabled => _halfRepsEnabled;
  bool get commentsEnabled => _commentsEnabled;
  bool get autoFinishWorkoutEnabled => _autoFinishWorkoutEnabled;
  int get autoFinishWorkoutHours => _autoFinishWorkoutHours;
  bool get autoFilterHistoryEnabled => _autoFilterHistoryEnabled;

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
    _checkAndAutoFinishOldWorkout();
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
      _weightUnit = settings['weightUnit'] as String? ?? 'kg';
      _distanceUnit = settings['distanceUnit'] as String? ?? 'km';
      _halfRepsEnabled = settings['halfRepsEnabled'] as bool? ?? false;
      _commentsEnabled = settings['commentsEnabled'] as bool? ?? true;
      _autoFinishWorkoutEnabled =
          settings['autoFinishWorkoutEnabled'] as bool? ?? false;
      _autoFinishWorkoutHours = settings['autoFinishWorkoutHours'] as int? ?? 4;
      _autoFilterHistoryEnabled =
          settings['autoFilterHistoryEnabled'] as bool? ?? false;
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
        'weightUnit': _weightUnit,
        'distanceUnit': _distanceUnit,
        'halfRepsEnabled': _halfRepsEnabled,
        'commentsEnabled': _commentsEnabled,
        'autoFinishWorkoutEnabled': _autoFinishWorkoutEnabled,
        'autoFinishWorkoutHours': _autoFinishWorkoutHours,
        'autoFilterHistoryEnabled': _autoFilterHistoryEnabled,
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

  void setWeightUnit(String unit) {
    if (unit != 'kg' && unit != 'lb') return;
    if (_weightUnit == unit) return;
    _weightUnit = unit;
    notifyListeners();
    unawaited(_persist());
  }

  void setDistanceUnit(String unit) {
    if (unit != 'km' && unit != 'mi') return;
    if (_distanceUnit == unit) return;
    _distanceUnit = unit;
    notifyListeners();
    unawaited(_persist());
  }

  void setHalfRepsEnabled(bool enabled) {
    if (_halfRepsEnabled == enabled) return;
    _halfRepsEnabled = enabled;
    notifyListeners();
    unawaited(_persist());
  }

  void setCommentsEnabled(bool enabled) {
    if (_commentsEnabled == enabled) return;
    _commentsEnabled = enabled;
    notifyListeners();
    unawaited(_persist());
  }

  void setAutoFinishWorkoutEnabled(bool enabled) {
    if (_autoFinishWorkoutEnabled == enabled) return;
    _autoFinishWorkoutEnabled = enabled;
    notifyListeners();
    unawaited(_persist());
  }

  void setAutoFinishWorkoutHours(int hours) {
    if (hours < 1) return; // Minimum 1 hour
    if (_autoFinishWorkoutHours == hours) return;
    _autoFinishWorkoutHours = hours;
    notifyListeners();
    unawaited(_persist());
  }

  void setAutoFilterHistoryEnabled(bool enabled) {
    if (_autoFilterHistoryEnabled == enabled) return;
    _autoFilterHistoryEnabled = enabled;
    notifyListeners();
    unawaited(_persist());
  }

  /// Returns the muscle group ID of the current active exercise,
  /// or the last logged exercise if no active exercise exists.
  /// Returns null if there's no active workout.
  String? get activeWorkoutMuscleGroupId {
    final session = _activeSession;
    if (session == null || session.exercises.isEmpty) {
      return null;
    }

    // First, try to get the current active exercise
    for (final exercise in session.exercises.reversed) {
      if (!exercise.isComplete) {
        return exercise.muscleGroupId;
      }
    }

    // If all exercises are complete, get the last logged exercise
    for (final exercise in session.exercises.reversed) {
      if (exercise.hasSets) {
        return exercise.muscleGroupId;
      }
    }

    return null;
  }

  void _checkAndAutoFinishOldWorkout() {
    if (!_autoFinishWorkoutEnabled) return;
    final session = _activeSession;
    if (session == null) return;

    final now = DateTime.now();
    final sessionAge = now.difference(session.startedAt);
    final threshold = Duration(hours: _autoFinishWorkoutHours);

    if (sessionAge >= threshold) {
      // Auto-finish the workout
      finishWorkout();
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
  /// Uses getCurrentPRs to ensure consistent logic between workout and history screens.
  bool isPersonalRecord(
    WorkoutSetEntry entry,
    WorkoutSet currentSet, {
    WorkoutSession? excludeSession,
  }) {
    // Only track PRs for single-exercise sets
    if (currentSet.entries.length > 1) {
      return false;
    }

    final prSets = getCurrentPRs(entry.exerciseId);
    return prSets.contains(currentSet.id);
  }

  /// Get current PR sets for a specific exercise.
  /// Returns set IDs that hold current PRs.
  ///
  /// PR Rules:
  /// 1. A set is a PR if at least one of its units (weight, reps, distance, time) is the highest
  /// 2. For ties, the first logged set (earliest timestamp) is considered the PR
  /// 3. For multi-unit exercises (e.g., weightReps), if a new set matches the max of one unit
  ///    but exceeds another unit, it becomes a PR for that unit
  Set<String> getCurrentPRs(String exerciseId) {
    final exercise = exerciseById(exerciseId);
    if (exercise == null) {
      return <String>{};
    }

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
      return <String>{};
    }

    final prSetIds = <String>{};

    switch (exercise.unit) {
      case ExerciseUnit.weightReps:
        _findPRsForWeightReps(allSets, prSetIds);
        break;
      case ExerciseUnit.reps:
        _findPRsForSingleMetric(allSets, prSetIds, (entry) => entry.reps ?? 0);
        break;
      case ExerciseUnit.time:
        _findPRsForSingleMetric(
          allSets,
          prSetIds,
          (entry) => entry.duration?.inSeconds ?? 0,
        );
        break;
      case ExerciseUnit.distanceTime:
        _findPRsForTwoMetrics(
          allSets,
          prSetIds,
          (entry) => entry.distance ?? 0,
          (entry) => entry.duration?.inSeconds ?? 0,
        );
        break;
      case ExerciseUnit.repsTime:
        _findPRsForTwoMetrics(
          allSets,
          prSetIds,
          (entry) => entry.reps ?? 0,
          (entry) => entry.duration?.inSeconds ?? 0,
        );
        break;
      case ExerciseUnit.distance:
        _findPRsForSingleMetric(
          allSets,
          prSetIds,
          (entry) => entry.distance ?? 0,
        );
        break;
    }

    return prSetIds;
  }

  /// Find PRs for exercises with weight and reps
  void _findPRsForWeightReps(
    List<({WorkoutSet set, WorkoutSetEntry entry})> allSets,
    Set<String> prSetIds,
  ) {
    // Find max values
    var maxWeight = 0.0;
    var maxReps = 0;

    for (final record in allSets) {
      final weight = record.entry.weight ?? 0;
      final reps = record.entry.reps ?? 0;
      if (weight > maxWeight) maxWeight = weight;
      if (reps > maxReps) maxReps = reps;
    }

    // Find PR for max weight
    // If multiple sets have max weight, pick the one with most reps
    // If reps are tied, pick the one with most half reps
    // If still tied, pick the earliest
    String? maxWeightSetId;
    var maxWeightBestReps = 0;
    var maxWeightBestHalfReps = 0;
    DateTime? maxWeightEarliestTime;

    for (final record in allSets) {
      final weight = record.entry.weight ?? 0;
      final reps = record.entry.reps ?? 0;
      final halfReps = record.entry.halfReps ?? 0;

      if (weight == maxWeight) {
        if (maxWeightSetId == null ||
            reps > maxWeightBestReps ||
            (reps == maxWeightBestReps && halfReps > maxWeightBestHalfReps) ||
            (reps == maxWeightBestReps &&
                halfReps == maxWeightBestHalfReps &&
                record.set.timestamp.isBefore(maxWeightEarliestTime!))) {
          maxWeightSetId = record.set.id;
          maxWeightBestReps = reps;
          maxWeightBestHalfReps = halfReps;
          maxWeightEarliestTime = record.set.timestamp;
        }
      }
    }

    // Find PR for max reps
    // If multiple sets have max reps, pick the one with most weight
    // If weight is tied, pick the one with most half reps
    // If still tied, pick the earliest
    String? maxRepsSetId;
    var maxRepsBestWeight = 0.0;
    var maxRepsBestHalfReps = 0;
    DateTime? maxRepsEarliestTime;

    for (final record in allSets) {
      final weight = record.entry.weight ?? 0;
      final reps = record.entry.reps ?? 0;
      final halfReps = record.entry.halfReps ?? 0;

      if (reps == maxReps) {
        if (maxRepsSetId == null ||
            weight > maxRepsBestWeight ||
            (weight == maxRepsBestWeight && halfReps > maxRepsBestHalfReps) ||
            (weight == maxRepsBestWeight &&
                halfReps == maxRepsBestHalfReps &&
                record.set.timestamp.isBefore(maxRepsEarliestTime!))) {
          maxRepsSetId = record.set.id;
          maxRepsBestWeight = weight;
          maxRepsBestHalfReps = halfReps;
          maxRepsEarliestTime = record.set.timestamp;
        }
      }
    }

    if (maxWeightSetId != null) prSetIds.add(maxWeightSetId);
    if (maxRepsSetId != null && maxRepsSetId != maxWeightSetId) {
      prSetIds.add(maxRepsSetId);
    }
  }

  /// Find PRs for exercises with a single metric
  void _findPRsForSingleMetric(
    List<({WorkoutSet set, WorkoutSetEntry entry})> allSets,
    Set<String> prSetIds,
    num Function(WorkoutSetEntry) getValue,
  ) {
    // Find max value
    num maxValue = 0;
    for (final record in allSets) {
      final value = getValue(record.entry);
      if (value > maxValue) maxValue = value;
    }

    // Find earliest set with max value
    for (final record in allSets) {
      final value = getValue(record.entry);
      if (value == maxValue) {
        prSetIds.add(record.set.id);
        break; // Only add the first (earliest) one
      }
    }
  }

  /// Find PRs for exercises with two metrics (e.g., distance & time, reps & time)
  void _findPRsForTwoMetrics(
    List<({WorkoutSet set, WorkoutSetEntry entry})> allSets,
    Set<String> prSetIds,
    num Function(WorkoutSetEntry) getValue1,
    num Function(WorkoutSetEntry) getValue2,
  ) {
    // Find max values for both metrics
    num maxValue1 = 0;
    num maxValue2 = 0;

    for (final record in allSets) {
      final value1 = getValue1(record.entry);
      final value2 = getValue2(record.entry);
      if (value1 > maxValue1) maxValue1 = value1;
      if (value2 > maxValue2) maxValue2 = value2;
    }

    // Find PR for first metric (earliest with max value1)
    String? maxValue1SetId;
    for (final record in allSets) {
      final value1 = getValue1(record.entry);
      if (value1 == maxValue1) {
        maxValue1SetId = record.set.id;
        break;
      }
    }

    // Find PR for second metric (earliest with max value2)
    String? maxValue2SetId;
    for (final record in allSets) {
      final value2 = getValue2(record.entry);
      if (value2 == maxValue2) {
        maxValue2SetId = record.set.id;
        break;
      }
    }

    if (maxValue1SetId != null) prSetIds.add(maxValue1SetId);
    if (maxValue2SetId != null && maxValue2SetId != maxValue1SetId) {
      prSetIds.add(maxValue2SetId);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
