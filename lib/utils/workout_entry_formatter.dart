import '../models/exercise.dart';
import '../models/workout.dart';

String formatWorkoutEntry(WorkoutSetEntry entry) {
  final List<String> parts = <String>[];

  switch (entry.unit) {
    case ExerciseUnit.weightReps:
      parts
        ..add(_formatDouble(entry.weight, suffix: 'kg'))
        ..add(_formatReps(entry.reps));
      break;
    case ExerciseUnit.reps:
      parts.add(_formatReps(entry.reps));
      break;
    case ExerciseUnit.time:
      parts.add(_formatDuration(entry.duration));
      break;
    case ExerciseUnit.distanceTime:
      parts.addAll(
        _formatCombined(
          _formatDouble(entry.distance, suffix: 'km'),
          _formatDuration(entry.duration),
          joiner: ' in ',
        ),
      );
      break;
    case ExerciseUnit.repsTime:
      parts.addAll(
        _formatCombined(
          _formatReps(entry.reps),
          _formatDuration(entry.duration),
          joiner: ' in ',
        ),
      );
      break;
    case ExerciseUnit.distance:
      parts.add(_formatDouble(entry.distance, suffix: 'km'));
      break;
  }

  final halfRepsText = _formatHalfReps(entry.halfReps);
  if (halfRepsText.isNotEmpty) {
    parts.add(halfRepsText);
  }

  final filtered = parts.where((part) => part.isNotEmpty).toList();
  if (filtered.isEmpty) {
    return '—';
  }
  return filtered.join(' • ');
}

List<String> _formatCombined(
  String first,
  String second, {
  required String joiner,
}) {
  if (first.isEmpty && second.isEmpty) {
    return const <String>[];
  }
  if (first.isNotEmpty && second.isNotEmpty) {
    return <String>['$first$joiner$second'];
  }
  return <String>[first.isNotEmpty ? first : second];
}

String _formatReps(int? reps) {
  if (reps == null || reps <= 0) {
    return '';
  }
  return '$reps reps';
}

String _formatHalfReps(int? halfReps) {
  if (halfReps == null || halfReps <= 0) {
    return '';
  }
  final suffix = halfReps == 1 ? 'half rep' : 'half reps';
  return '$halfReps $suffix';
}

String _formatDouble(double? value, {required String suffix}) {
  if (value == null || value <= 0) {
    return '';
  }
  final isWholeNumber = value.roundToDouble() == value;
  final formatted = isWholeNumber
      ? value.toStringAsFixed(0)
      : value
            .toStringAsFixed(2)
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
  return suffix.isEmpty ? formatted : '$formatted $suffix';
}

String _formatDuration(Duration? duration) {
  if (duration == null || duration.inSeconds <= 0) {
    return '';
  }
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  if (minutes > 0) {
    final secondsPart = seconds.toString().padLeft(2, '0');
    if (seconds == 0) {
      return '${minutes}m';
    }
    return '${minutes}m ${secondsPart}s';
  }
  return '${duration.inSeconds}s';
}
