import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repwise/providers/repwise_provider.dart';
import 'package:repwise/utils/repwise_storage.dart';

class _NoOpStorage extends RepwiseStorage {
  const _NoOpStorage();

  @override
  Future<Map<String, dynamic>?> readState() async => null;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {}

  @override
  Future<File?> createExportFile(Map<String, dynamic> state) async => null;
}

const _muscleGroupId = 'mg-chest';
const _exerciseId = 'ex-bench';
const _altMuscleGroupId = 'mg-back';
const _altExerciseId = 'ex-row';

/// Builds a provider pre-loaded with sessions on specified dates.
/// [chestDates] and [backDates]: ISO-8601 date strings e.g. '2026-06-01'.
Future<RepwiseProvider> _buildProvider({
  List<String> chestDates = const [],
  List<String> backDates = const [],
}) async {
  int counter = 0;
  String nextId() => 'id-${counter++}';

  Map<String, dynamic> makeSession(
    String muscleGroupId,
    String exerciseId,
    String date,
  ) {
    final id = nextId();
    return {
      'id': 'session-$id',
      'startedAt': '${date}T10:00:00.000',
      'exercises': [
        {
          'id': 'exlog-$id',
          'muscleGroupId': muscleGroupId,
          'exerciseIds': [exerciseId],
          'startedAt': '${date}T10:00:00.000',
          'finishedAt': '${date}T10:30:00.000',
          'sets': [
            {
              'id': 'set-$id',
              'muscleGroupId': muscleGroupId,
              'timestamp': '${date}T10:00:00.000',
              'entries': [
                {'exerciseId': exerciseId, 'unit': 'reps', 'reps': 10},
              ],
            },
          ],
        },
      ],
    };
  }

  final sessions = [
    ...chestDates.map((d) => makeSession(_muscleGroupId, _exerciseId, d)),
    ...backDates.map((d) => makeSession(_altMuscleGroupId, _altExerciseId, d)),
  ];

  final json = jsonEncode({
    'muscleGroups': [
      {
        'id': _muscleGroupId,
        'name': 'Chest',
        'exercises': [
          {'id': _exerciseId, 'name': 'Bench Press', 'unit': 'reps'},
        ],
      },
      {
        'id': _altMuscleGroupId,
        'name': 'Back',
        'exercises': [
          {'id': _altExerciseId, 'name': 'Row', 'unit': 'reps'},
        ],
      },
    ],
    'completedSessions': sessions,
    'settings': {},
  });

  final provider = RepwiseProvider(storage: const _NoOpStorage());
  final success = await provider.importFromJson(json);
  expect(success, isTrue, reason: 'importFromJson should succeed');
  return provider;
}

DateTime _date(String iso) => DateTime.parse(iso);

void main() {
  group('previousWorkoutDay', () {
    test('returns the closest past day with any workout', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-01', '2026-06-05', '2026-06-10'],
      );
      expect(
        p.previousWorkoutDay(_date('2026-06-11')),
        equals(_date('2026-06-10')),
      );
    });

    test('ignores the boundary date itself (strictly before)', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-10', '2026-06-11'],
      );
      expect(
        p.previousWorkoutDay(_date('2026-06-11')),
        equals(_date('2026-06-10')),
      );
    });

    test('returns null when no workouts exist before the date', () async {
      final p = await _buildProvider(chestDates: ['2026-06-15']);
      expect(p.previousWorkoutDay(_date('2026-06-10')), isNull);
    });

    test('filters by muscleGroupIds when provided', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-01', '2026-06-05'],
        backDates: ['2026-06-08'],
      );
      expect(
        p.previousWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        equals(_date('2026-06-08')),
      );
    });

    test('ignores non-matching muscle groups when filter is active', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-05', '2026-06-09'],
        backDates: ['2026-06-08'],
      );
      expect(
        p.previousWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        equals(_date('2026-06-08')),
      );
    });

    test('returns null when filter matches no sessions before the date', () async {
      final p = await _buildProvider(backDates: ['2026-06-15']);
      expect(
        p.previousWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        isNull,
      );
    });
  });

  group('nextWorkoutDay', () {
    test('returns the closest future day with any workout', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-10', '2026-06-15', '2026-06-20'],
      );
      expect(
        p.nextWorkoutDay(_date('2026-06-09')),
        equals(_date('2026-06-10')),
      );
    });

    test('ignores the boundary date itself (strictly after)', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-10', '2026-06-11'],
      );
      expect(
        p.nextWorkoutDay(_date('2026-06-10')),
        equals(_date('2026-06-11')),
      );
    });

    test('returns null when no workouts exist after the date', () async {
      final p = await _buildProvider(chestDates: ['2026-06-01']);
      expect(p.nextWorkoutDay(_date('2026-06-10')), isNull);
    });

    test('filters by muscleGroupIds when provided', () async {
      final p = await _buildProvider(
        chestDates: ['2026-06-12'],
        backDates: ['2026-06-15'],
      );
      expect(
        p.nextWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        equals(_date('2026-06-15')),
      );
    });

    test('returns null when filter matches no sessions after the date', () async {
      final p = await _buildProvider(chestDates: ['2026-06-15']);
      expect(
        p.nextWorkoutDay(
          _date('2026-06-10'),
          muscleGroupIds: {_altMuscleGroupId},
        ),
        isNull,
      );
    });
  });
}