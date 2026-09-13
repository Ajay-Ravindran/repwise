import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:repwise/models/exercise.dart';
import 'package:repwise/providers/repwise_provider.dart';
import 'package:repwise/screens/workout_screen.dart';
import 'package:repwise/utils/repwise_storage.dart';

class _NoOpStorage extends RepwiseStorage {
  const _NoOpStorage();

  @override
  Future<Map<String, dynamic>?> readState() async => null;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {}
}

Future<RepwiseProvider> _buildProviderWithTimeExercise() async {
  final provider = RepwiseProvider(storage: const _NoOpStorage());
  await provider.initialize();
  provider.addMuscleGroup('Core');
  final group = provider.muscleGroups.single;
  provider.addExercise(group.id, 'Plank', ExerciseUnit.time);
  provider.startWorkout();
  return provider;
}

void main() {
  testWidgets('Add Set sheet shows separate Minutes and Seconds fields', (
    WidgetTester tester,
  ) async {
    final provider = await _buildProviderWithTimeExercise();
    final group = provider.muscleGroups.single;
    final exercise = group.exercises.single;

    provider.startExercise(
      muscleGroupId: group.id,
      exerciseIds: [exercise.id],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<RepwiseProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => WorkoutScreen.showAddSetSheet(
                  context,
                  exerciseLog: provider.activeExercise!,
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
    await tester.tap(
      find.ancestor(
        of: find.text('Add Set'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    final loggedSet = provider.activeExercise!.sets.single;
    expect(loggedSet.entries.single.duration, equals(const Duration(seconds: 90)));
  });
}
