/// A single daily body-weight log entry. If a user logs their weight more
/// than once on the same [date], the latest value wins — callers (the
/// provider) are responsible for overwriting rather than duplicating.
class WeightEntry {
  WeightEntry({
    required this.id,
    required this.date,
    required this.weight,
    required this.loggedAt,
  });

  /// Unique identifier for this entry.
  final String id;

  /// The calendar day this weight applies to (time-of-day is not meaningful
  /// and should always be midnight).
  final DateTime date;

  /// The logged weight, in whatever unit (kg/lb) was active when logged.
  final double weight;

  /// The exact timestamp the entry was created/last overwritten.
  final DateTime loggedAt;

  WeightEntry copyWith({
    String? id,
    DateTime? date,
    double? weight,
    DateTime? loggedAt,
  }) {
    return WeightEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      weight: weight ?? this.weight,
      loggedAt: loggedAt ?? this.loggedAt,
    );
  }

  factory WeightEntry.fromJson(Map<String, dynamic> json) {
    return WeightEntry(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      weight: (json['weight'] as num).toDouble(),
      loggedAt: DateTime.parse(json['loggedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'date': date.toIso8601String(),
      'weight': weight,
      'loggedAt': loggedAt.toIso8601String(),
    };
  }
}
