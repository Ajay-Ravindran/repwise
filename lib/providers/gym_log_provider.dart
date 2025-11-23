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
    _completedSessions.insert(0, _activeSession!);
    _activeSession = null;
    notifyListeners();
    unawaited(_persist());
  }

  bool addSet({
    required String muscleGroupId,
    required List<WorkoutSetEntry> entries,
  }) {
    final session = _activeSession;
    if (session == null || entries.isEmpty) {
      return false;
    }
    final hasGroup = _muscleGroups.any((group) => group.id == muscleGroupId);
    if (!hasGroup) {
      return false;
    }
    final validEntries = entries
        .where((entry) => entry.hasMetrics)
        .toList(growable: false);
    if (validEntries.isEmpty) {
      return false;
    }
    final set = WorkoutSet(
      id: _uuid.v4(),
      muscleGroupId: muscleGroupId,
      entries: validEntries,
      timestamp: DateTime.now(),
    );
    session.sets.add(set);
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool updateSet({
    required String setId,
    required String muscleGroupId,
    required List<WorkoutSetEntry> entries,
  }) {
    final session = _activeSession;
    if (session == null || entries.isEmpty) {
      return false;
    }
    final setIndex = session.sets.indexWhere((set) => set.id == setId);
    if (setIndex == -1) {
      return false;
    }
    final hasGroup = _muscleGroups.any((group) => group.id == muscleGroupId);
    if (!hasGroup) {
      return false;
    }
    final validEntries = entries
        .where((entry) => entry.hasMetrics)
        .toList(growable: false);
    if (validEntries.isEmpty) {
      return false;
    }
    final existing = session.sets[setIndex];
    session.sets[setIndex] = WorkoutSet(
      id: existing.id,
      muscleGroupId: muscleGroupId,
      entries: validEntries,
      timestamp: existing.timestamp,
    );
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool removeActiveSet(String setId) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    final index = session.sets.indexWhere((set) => set.id == setId);
    if (index == -1) {
      return false;
    }
    session.sets.removeAt(index);
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool reorderActiveSet(int oldIndex, int newIndex) {
    final session = _activeSession;
    if (session == null) {
      return false;
    }
    if (oldIndex < 0 || oldIndex >= session.sets.length) {
      return false;
    }
    if (newIndex < 0 || newIndex > session.sets.length) {
      return false;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final moved = session.sets.removeAt(oldIndex);
    session.sets.insert(newIndex, moved);
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  bool removeCompletedSet({required String sessionId, required String setId}) {
    final sessionIndex = _completedSessions.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      return false;
    }
    final session = _completedSessions[sessionIndex];
    final setIndex = session.sets.indexWhere((set) => set.id == setId);
    if (setIndex == -1) {
      return false;
    }
    session.sets.removeAt(setIndex);
    if (session.sets.isEmpty) {
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

  DateTime _dateOnly(DateTime dateTime) =>
      DateTime(dateTime.year, dateTime.month, dateTime.day);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
