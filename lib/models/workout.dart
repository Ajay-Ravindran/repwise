import 'exercise.dart';

class WorkoutSetEntry {
  WorkoutSetEntry({
    required this.exerciseId,
    required this.unit,
    this.reps,
    this.weight,
    this.distance,
    this.duration,
    this.halfReps,
    this.comment,
  });

  final String exerciseId;
  final ExerciseUnit unit;
  final int? reps;
  final double? weight;
  final double? distance;
  final Duration? duration;
  final int? halfReps;
  final String? comment;

  bool get hasMetrics {
    final hasReps = (reps ?? 0) > 0;
    final hasWeight = (weight ?? 0) > 0;
    final hasDistance = (distance ?? 0) > 0;
    final hasDuration = duration != null && duration!.inSeconds > 0;
    final hasHalfReps = (halfReps ?? 0) > 0;
    return hasReps || hasHalfReps || hasWeight || hasDistance || hasDuration;
  }

  factory WorkoutSetEntry.fromJson(Map<String, dynamic> json) {
    return WorkoutSetEntry(
      exerciseId: json['exerciseId'] as String,
      unit: exerciseUnitFromCode(json['unit'] as String),
      reps: json['reps'] as int?,
      weight: (json['weight'] as num?)?.toDouble(),
      distance: (json['distance'] as num?)?.toDouble(),
      duration: json['durationSeconds'] is int
          ? Duration(seconds: json['durationSeconds'] as int)
          : null,
      halfReps: (json['halfReps'] as num?)?.toInt(),
      comment: () {
        final raw = json['comment'];
        if (raw is! String) {
          return null;
        }
        final trimmed = raw.trim();
        return trimmed.isEmpty ? null : trimmed;
      }(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'exerciseId': exerciseId,
      'unit': unit.code,
      'reps': reps,
      'weight': weight,
      'distance': distance,
      'durationSeconds': duration?.inSeconds,
      'halfReps': halfReps,
      'comment': comment,
    };
  }
}

class WorkoutSet {
  WorkoutSet({
    required this.id,
    required this.muscleGroupId,
    required this.entries,
    required this.timestamp,
  });

  final String id;
  final String muscleGroupId;
  final List<WorkoutSetEntry> entries;
  final DateTime timestamp;

  bool get isSuperset => entries.length > 1;

  factory WorkoutSet.fromJson(Map<String, dynamic> json) {
    final entriesJson = json['entries'] as List<dynamic>? ?? const [];
    return WorkoutSet(
      id: json['id'] as String,
      muscleGroupId: json['muscleGroupId'] as String,
      entries: entriesJson
          .whereType<Map<String, dynamic>>()
          .map(WorkoutSetEntry.fromJson)
          .toList(),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'muscleGroupId': muscleGroupId,
      'entries': entries.map((entry) => entry.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class WorkoutExerciseLog {
  WorkoutExerciseLog({
    required this.id,
    required this.muscleGroupId,
    required List<String> exerciseIds,
    List<WorkoutSet>? sets,
    DateTime? startedAt,
    this.finishedAt,
  }) : exerciseIds = Set<String>.from(exerciseIds).toList(),
       sets = sets ?? <WorkoutSet>[],
       startedAt = startedAt ?? DateTime.now();

  final String id;
  final String muscleGroupId;
  final List<String> exerciseIds;
  final List<WorkoutSet> sets;
  final DateTime startedAt;
  DateTime? finishedAt;

  bool get hasSets => sets.isNotEmpty;
  bool get isSuperset => exerciseIds.length > 1;
  bool get isComplete => finishedAt != null;

  factory WorkoutExerciseLog.fromJson(Map<String, dynamic> json) {
    final setsJson = json['sets'] as List<dynamic>? ?? const [];
    final parsedSets = setsJson
        .whereType<Map<String, dynamic>>()
        .map(WorkoutSet.fromJson)
        .toList();
    final rawIds = json['exerciseIds'];
    final parsedIds = rawIds is List
        ? Set<String>.from(rawIds.whereType<String>()).toList()
        : <String>[];
    final inferredIds = parsedIds.isEmpty
        ? parsedSets
              .expand((set) => set.entries.map((entry) => entry.exerciseId))
              .toSet()
              .toList()
        : parsedIds;
    return WorkoutExerciseLog(
      id: json['id'] as String,
      muscleGroupId: json['muscleGroupId'] as String,
      exerciseIds: inferredIds,
      sets: parsedSets,
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          (parsedSets.isNotEmpty ? parsedSets.first.timestamp : DateTime.now()),
      finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'muscleGroupId': muscleGroupId,
      'exerciseIds': exerciseIds,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt?.toIso8601String(),
      'sets': sets.map((set) => set.toJson()).toList(),
    };
  }
}

class WorkoutSession {
  WorkoutSession({
    required this.id,
    required this.startedAt,
    List<WorkoutExerciseLog>? exercises,
  }) : exercises = exercises ?? <WorkoutExerciseLog>[];

  final String id;
  final DateTime startedAt;
  final List<WorkoutExerciseLog> exercises;

  @Deprecated('Use exercises or allSets instead.')
  List<WorkoutSet> get sets => List<WorkoutSet>.unmodifiable(allSets);

  Iterable<WorkoutSet> get allSets =>
      exercises.expand((exercise) => exercise.sets);

  factory WorkoutSession.fromJson(Map<String, dynamic> json) {
    final exercisesJson = json['exercises'] as List<dynamic>?;
    List<WorkoutExerciseLog> parsedExercises;
    if (exercisesJson != null) {
      parsedExercises = exercisesJson
          .whereType<Map<String, dynamic>>()
          .map(WorkoutExerciseLog.fromJson)
          .toList();
    } else {
      final legacySetsJson = json['sets'] as List<dynamic>? ?? const [];
      parsedExercises = legacySetsJson
          .whereType<Map<String, dynamic>>()
          .map(WorkoutSet.fromJson)
          .map(
            (set) => WorkoutExerciseLog(
              id: set.id,
              muscleGroupId: set.muscleGroupId,
              exerciseIds: set.entries
                  .map((entry) => entry.exerciseId)
                  .toSet()
                  .toList(),
              sets: <WorkoutSet>[set],
              startedAt: set.timestamp,
              finishedAt: set.timestamp,
            ),
          )
          .toList();
    }
    return WorkoutSession(
      id: json['id'] as String,
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.now(),
      exercises: parsedExercises,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'startedAt': startedAt.toIso8601String(),
      'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
    };
  }
}
