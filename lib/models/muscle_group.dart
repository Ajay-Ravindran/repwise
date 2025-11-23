import 'exercise.dart';

class MuscleGroup {
  MuscleGroup({required this.id, required this.name, List<Exercise>? exercises})
    : exercises = exercises ?? <Exercise>[];

  final String id;
  final String name;
  final List<Exercise> exercises;

  MuscleGroup copyWith({String? id, String? name, List<Exercise>? exercises}) {
    return MuscleGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      exercises: exercises ?? List<Exercise>.from(this.exercises),
    );
  }

  factory MuscleGroup.fromJson(Map<String, dynamic> json) {
    final exercisesJson = json['exercises'] as List<dynamic>? ?? const [];
    return MuscleGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      exercises: exercisesJson
          .whereType<Map<String, dynamic>>()
          .map(Exercise.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
    };
  }
}
