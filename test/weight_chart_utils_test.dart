import 'package:flutter_test/flutter_test.dart';
import 'package:repwise/models/weight_entry.dart';
import 'package:repwise/utils/weight_chart_utils.dart';

WeightEntry _entry(String iso, double weight) {
  return WeightEntry(
    id: iso,
    date: DateTime.parse(iso),
    weight: weight,
    loggedAt: DateTime.parse(iso),
  );
}

void main() {
  group('bucketWeightEntries', () {
    test('day granularity returns one point per entry, sorted', () {
      final entries = [
        _entry('2026-06-02', 81.0),
        _entry('2026-06-01', 82.0),
      ];

      final points = bucketWeightEntries(entries, Granularity.day);

      expect(points.length, equals(2));
      expect(points[0].bucketStart, equals(DateTime(2026, 6, 1)));
      expect(points[0].weight, equals(82.0));
      expect(points[1].bucketStart, equals(DateTime(2026, 6, 2)));
      expect(points[1].weight, equals(81.0));
    });

    test('week granularity picks the lowest weight per ISO week', () {
      // 2026-06-01 is a Monday; 2026-06-03 is in the same week.
      final entries = [
        _entry('2026-06-01', 82.0),
        _entry('2026-06-03', 80.5),
        _entry('2026-06-08', 79.0), // next week (Monday)
      ];

      final points = bucketWeightEntries(entries, Granularity.week);

      expect(points.length, equals(2));
      expect(points[0].weight, equals(80.5));
      expect(points[0].bucketStart, equals(DateTime(2026, 6, 1)));
      expect(points[1].weight, equals(79.0));
      expect(points[1].bucketStart, equals(DateTime(2026, 6, 8)));
    });

    test('month granularity picks the lowest weight per calendar month', () {
      final entries = [
        _entry('2026-06-01', 82.0),
        _entry('2026-06-20', 79.5),
        _entry('2026-07-05', 80.0),
      ];

      final points = bucketWeightEntries(entries, Granularity.month);

      expect(points.length, equals(2));
      expect(points[0].weight, equals(79.5));
      expect(points[0].bucketStart, equals(DateTime(2026, 6, 1)));
      expect(points[1].weight, equals(80.0));
      expect(points[1].bucketStart, equals(DateTime(2026, 7, 1)));
    });

    test('returns an empty list for no entries', () {
      expect(bucketWeightEntries(const [], Granularity.day), isEmpty);
    });
  });

  group('formatBucketLabel', () {
    test('day/week use "d MMM", month uses "MMM yyyy"', () {
      final date = DateTime(2026, 6, 1);
      expect(formatBucketLabel(date, Granularity.day), equals('1 Jun'));
      expect(formatBucketLabel(date, Granularity.week), equals('1 Jun'));
      expect(formatBucketLabel(date, Granularity.month), equals('Jun 2026'));
    });
  });

  group('stats helpers', () {
    test('latestWeight returns the most recent entry weight', () {
      final entries = [_entry('2026-06-01', 82.0), _entry('2026-06-05', 80.0)];
      expect(latestWeight(entries), equals(80.0));
    });

    test('latestWeight returns null for no entries', () {
      expect(latestWeight(const []), isNull);
    });

    test('weightChangeOverDays compares latest to the closest entry at/before the cutoff', () {
      final entries = [
        _entry('2026-05-25', 84.0),
        _entry('2026-06-01', 82.0),
        _entry('2026-06-08', 80.0),
      ];

      // Reference = 2026-06-08, 7-day cutoff = 2026-06-01 -> baseline 82.0.
      final change = weightChangeOverDays(
        entries,
        7,
        referenceDate: DateTime(2026, 6, 8),
      );

      expect(change, equals(80.0 - 82.0));
    });

    test('weightChangeOverDays returns null when there is only one entry', () {
      final entries = [_entry('2026-06-01', 82.0)];
      expect(weightChangeOverDays(entries, 7), isNull);
    });

    test('minWeight and maxWeight scan all entries', () {
      final entries = [
        _entry('2026-06-01', 82.0),
        _entry('2026-06-05', 79.0),
        _entry('2026-06-08', 85.0),
      ];
      expect(minWeight(entries), equals(79.0));
      expect(maxWeight(entries), equals(85.0));
    });
  });
}
