enum ExerciseUnit {
  weightReps,
  reps,
  time,
  distanceTime,
  repsTime,
  distance,
  weightTime,
}

extension ExerciseUnitX on ExerciseUnit {
  String get label {
    switch (this) {
      case ExerciseUnit.weightReps:
        return 'Weight & Reps';
      case ExerciseUnit.reps:
        return 'Reps';
      case ExerciseUnit.time:
        return 'Time';
      case ExerciseUnit.distanceTime:
        return 'Distance & Time';
      case ExerciseUnit.repsTime:
        return 'Reps & Time';
      case ExerciseUnit.distance:
        return 'Distance';
      case ExerciseUnit.weightTime:
        return 'Weight & Time';
    }
  }

  String get code => name;
}

ExerciseUnit exerciseUnitFromCode(String code) {
  for (final unit in ExerciseUnit.values) {
    if (unit.name == code || unit.toString().split('.').last == code) {
      return unit;
    }
  }
  return ExerciseUnit.reps;
}

class Exercise {
  Exercise({required this.id, required this.name, required this.unit});

  final String id;
  final String name;
  final ExerciseUnit unit;

  Exercise copyWith({String? id, String? name, ExerciseUnit? unit}) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
    );
  }

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      name: json['name'] as String,
      unit: exerciseUnitFromCode(json['unit'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'id': id, 'name': name, 'unit': unit.code};
  }
}
