import 'package:flutter_test/flutter_test.dart';
import 'package:repwise/models/weight_entry.dart';

void main() {
  group('WeightEntry', () {
    test('round-trips through toJson/fromJson', () {
      final entry = WeightEntry(
        id: 'w1',
        date: DateTime(2026, 6, 1),
        weight: 82.5,
        loggedAt: DateTime(2026, 6, 1, 8, 30),
      );

      final decoded = WeightEntry.fromJson(entry.toJson());

      expect(decoded.id, equals('w1'));
      expect(decoded.date, equals(DateTime(2026, 6, 1)));
      expect(decoded.weight, equals(82.5));
      expect(decoded.loggedAt, equals(DateTime(2026, 6, 1, 8, 30)));
    });

    test('copyWith overrides only the given fields', () {
      final entry = WeightEntry(
        id: 'w1',
        date: DateTime(2026, 6, 1),
        weight: 82.5,
        loggedAt: DateTime(2026, 6, 1, 8, 30),
      );

      final updated = entry.copyWith(weight: 81.0);

      expect(updated.id, equals('w1'));
      expect(updated.date, equals(DateTime(2026, 6, 1)));
      expect(updated.weight, equals(81.0));
      expect(updated.loggedAt, equals(DateTime(2026, 6, 1, 8, 30)));
    });
  });
}
