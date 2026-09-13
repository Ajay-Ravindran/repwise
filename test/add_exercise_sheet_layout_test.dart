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

Future<RepwiseProvider> _buildProviderWithManyExercises() async {
  final provider = RepwiseProvider(storage: const _NoOpStorage());
  await provider.initialize();
  provider.addMuscleGroup('Legs');
  final group = provider.muscleGroups.single;
  for (var i = 0; i < 25; i++) {
    provider.addExercise(group.id, 'Leg exercise $i', ExerciseUnit.reps);
  }
  provider.startWorkout();
  return provider;
}

void main() {
  testWidgets(
    '"Add Exercise" button stays visible without scrolling when a muscle '
    'group has many exercises',
    (WidgetTester tester) async {
      final provider = await _buildProviderWithManyExercises();

      await tester.pumpWidget(
        ChangeNotifierProvider<RepwiseProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      WorkoutScreen.showStartExerciseSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // `FilledButton.icon` builds an internal subtype (`_FilledButtonWithIcon`)
      // rather than `FilledButton` itself, so we look for any `FilledButton`
      // subtype that is an ancestor of the "Add Exercise" label.
      final addExerciseButton = find.ancestor(
        of: find.text('Add Exercise'),
        matching: find.bySubtype<FilledButton>(),
      );

      // The button must be immediately visible without any scrolling,
      // i.e. it renders within the (finite) test viewport straight away.
      expect(addExerciseButton, findsOneWidget);
      expect(
        tester.getRect(addExerciseButton).bottom,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
    },
  );
}
