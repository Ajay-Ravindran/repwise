import '../models/weight_entry.dart';

enum Granularity { day, week, month }

/// One point to plot on the weight line chart.
class ChartPoint {
  ChartPoint({required this.bucketStart, required this.weight});

  final DateTime bucketStart;
  final double weight;
}

const List<String> _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

DateTime _dateOnly(DateTime dateTime) =>
    DateTime(dateTime.year, dateTime.month, dateTime.day);

DateTime _startOfWeek(DateTime date) {
  final dateOnly = _dateOnly(date);
  return dateOnly.subtract(Duration(days: dateOnly.weekday - DateTime.monday));
}

DateTime _startOfMonth(DateTime date) => DateTime(date.year, date.month, 1);

/// Buckets [entries] by [granularity]. For `day`, every entry becomes its
/// own point. For `week`/`month`, entries are grouped by ISO week / calendar
/// month and the **lowest** weight in each bucket is plotted, per the app's
/// weight-tracking spec. Returned points are sorted ascending by date.
List<ChartPoint> bucketWeightEntries(
  List<WeightEntry> entries,
  Granularity granularity,
) {
  if (entries.isEmpty) {
    return const <ChartPoint>[];
  }

  final sorted = List<WeightEntry>.from(entries)
    ..sort((a, b) => a.date.compareTo(b.date));

  if (granularity == Granularity.day) {
    return sorted
        .map(
          (entry) =>
              ChartPoint(bucketStart: _dateOnly(entry.date), weight: entry.weight),
        )
        .toList();
  }

  final DateTime Function(DateTime) bucketKeyFn =
      granularity == Granularity.week ? _startOfWeek : _startOfMonth;

  final Map<DateTime, double> lowestByBucket = <DateTime, double>{};
  for (final entry in sorted) {
    final key = bucketKeyFn(entry.date);
    final current = lowestByBucket[key];
    if (current == null || entry.weight < current) {
      lowestByBucket[key] = entry.weight;
    }
  }

  final sortedKeys = lowestByBucket.keys.toList()..sort();
  return sortedKeys
      .map((key) => ChartPoint(bucketStart: key, weight: lowestByBucket[key]!))
      .toList();
}

/// Formats a bucket's date for the chart's x-axis labels.
String formatBucketLabel(DateTime date, Granularity granularity) {
  switch (granularity) {
    case Granularity.day:
    case Granularity.week:
      return '${date.day} ${_monthAbbreviations[date.month - 1]}';
    case Granularity.month:
      return '${_monthAbbreviations[date.month - 1]} ${date.year}';
  }
}

/// The most recently logged weight, or null if there are no entries.
double? latestWeight(List<WeightEntry> entries) {
  if (entries.isEmpty) {
    return null;
  }
  final sorted = List<WeightEntry>.from(entries)
    ..sort((a, b) => a.date.compareTo(b.date));
  return sorted.last.weight;
}

/// The change in weight (latest - baseline) where baseline is the closest
/// entry at or before (`referenceDate` (defaults to the latest entry's date)
/// minus [days]). Returns null if there's no earlier entry to compare against.
double? weightChangeOverDays(
  List<WeightEntry> entries,
  int days, {
  DateTime? referenceDate,
}) {
  if (entries.length < 2) {
    return null;
  }
  final sorted = List<WeightEntry>.from(entries)
    ..sort((a, b) => a.date.compareTo(b.date));
  final latest = sorted.last;
  final reference = referenceDate ?? latest.date;
  final cutoff = reference.subtract(Duration(days: days));

  WeightEntry? baseline;
  for (final entry in sorted) {
    if (!entry.date.isAfter(cutoff)) {
      baseline = entry;
    } else {
      break;
    }
  }
  baseline ??= sorted.first;

  if (baseline.date.isAtSameMomentAs(latest.date)) {
    return null;
  }
  return latest.weight - baseline.weight;
}

/// The lowest weight ever logged, or null if there are no entries.
double? minWeight(List<WeightEntry> entries) {
  if (entries.isEmpty) {
    return null;
  }
  return entries.map((entry) => entry.weight).reduce((a, b) => a < b ? a : b);
}

/// The highest weight ever logged, or null if there are no entries.
double? maxWeight(List<WeightEntry> entries) {
  if (entries.isEmpty) {
    return null;
  }
  return entries.map((entry) => entry.weight).reduce((a, b) => a > b ? a : b);
}
