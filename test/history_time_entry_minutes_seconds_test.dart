import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:repwise/models/exercise.dart';
import 'package:repwise/models/workout.dart';
import 'package:repwise/providers/repwise_provider.dart';
import 'package:repwise/screens/history_screen.dart';
import 'package:repwise/utils/repwise_storage.dart';

class _NoOpStorage extends RepwiseStorage {
  const _NoOpStorage();

  @override
  Future<Map<String, dynamic>?> readState() async => null;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {}
}

Future<
  ({
    RepwiseProvider provider,
    String sessionId,
    String exerciseLogId,
    WorkoutExerciseLog exerciseLog,
    WorkoutSet initialSet,
  })
>
_buildProviderWithCompletedTimeSet() async {
  final provider = RepwiseProvider(storage: const _NoOpStorage());
  await provider.initialize();
  provider.addMuscleGroup('Core');
  final group = provider.muscleGroups.single;
  provider.addExercise(group.id, 'Plank', ExerciseUnit.time);
  final exercise = provider.muscleGroups.single.exercises.single;

  provider.startWorkout();
  final log = provider.startExercise(
    muscleGroupId: group.id,
    exerciseIds: [exercise.id],
  )!;
  provider.addSetToExercise(
    exerciseLogId: log.id,
    entries: [
      WorkoutSetEntry(
        exerciseId: exercise.id,
        unit: ExerciseUnit.time,
        duration: const Duration(seconds: 45),
      ),
    ],
  );
  provider.completeExercise(log.id);
  provider.finishWorkout();

  final completedSession = provider.completedSessions.single;
  final completedLog = completedSession.exercises.single;
  final completedSet = completedLog.sets.single;

  return (
    provider: provider,
    sessionId: completedSession.id,
    exerciseLogId: completedLog.id,
    exerciseLog: completedLog,
    initialSet: completedSet,
  );
}

void main() {
  testWidgets(
    'History edit-set dialog shows separate Minutes and Seconds fields '
    'and saves the combined duration',
    (WidgetTester tester) async {
      final data = await _buildProviderWithCompletedTimeSet();
      final provider = data.provider;

      await tester.pumpWidget(
        ChangeNotifierProvider<RepwiseProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showHistorySetEditDialog(
                    context,
                    exerciseLog: data.exerciseLog,
                    initialSet: data.initialSet,
                    sessionId: data.sessionId,
                    exerciseLogId: data.exerciseLogId,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Minutes'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Seconds'), findsOneWidget);
      expect(find.text('Time (seconds)'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minutes'),
        '1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Seconds'),
        '30',
      );

      await tester.tap(find.text('Update Set'));
      await tester.pumpAndSettle();

      final updatedSet = provider
          .completedSessions
          .single
          .exercises
          .single
          .sets
          .single;
      expect(
        updatedSet.entries.single.duration,
        equals(const Duration(seconds: 90)),
      );
    },
  );
}
