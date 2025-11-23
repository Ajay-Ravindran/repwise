import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/exercise.dart';
import '../models/muscle_group.dart';
import '../providers/gym_log_provider.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  static Future<void> showAddMuscleGroupDialog(BuildContext context) async {
    final provider = context.read<GymLogProvider>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _TextEntryDialog(
        title: 'New Muscle Group',
        hintText: 'e.g. Chest',
      ),
    );
    if (result == null) {
      return;
    }
    provider.addMuscleGroup(result);
  }

  static Future<void> showAddExerciseDialog(
    BuildContext context,
    MuscleGroup group,
  ) async {
    final provider = context.read<GymLogProvider>();
    final result = await showDialog<_ExerciseDialogResult>(
      context: context,
      builder: (dialogContext) => _ExerciseDialog(
        groupName: group.name,
        title: 'New Exercise',
        confirmLabel: 'Add',
      ),
    );
    if (result == null) {
      return;
    }
    provider.addExercise(group.id, result.name, result.unit);
  }

  static Future<void> showEditMuscleGroupDialog(
    BuildContext context,
    MuscleGroup group,
  ) async {
    final provider = context.read<GymLogProvider>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _TextEntryDialog(
        title: 'Edit Muscle Group',
        hintText: 'Update the muscle group name',
        initialValue: group.name,
        confirmLabel: 'Save',
      ),
    );
    if (result == null) {
      return;
    }
    provider.updateMuscleGroup(group.id, result);
  }

  static Future<void> showEditExerciseDialog(
    BuildContext context,
    MuscleGroup group,
    Exercise exercise,
  ) async {
    final provider = context.read<GymLogProvider>();
    final result = await showDialog<_ExerciseDialogResult>(
      context: context,
      builder: (dialogContext) => _ExerciseDialog(
        groupName: group.name,
        title: 'Edit Exercise',
        confirmLabel: 'Save',
        initialName: exercise.name,
        initialUnit: exercise.unit,
      ),
    );
    if (result == null) {
      return;
    }
    provider.updateExercise(
      muscleGroupId: group.id,
      exerciseId: exercise.id,
      name: result.name,
      unit: result.unit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GymLogProvider>();
    final groups = provider.muscleGroups;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Muscle Groups',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FilledButton.icon(
                onPressed: () => showAddMuscleGroupDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: groups.isEmpty
                ? const _EmptyState(
                    message: 'Add your first muscle group to get started.',
                  )
                : ListView.separated(
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    group.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: () =>
                                            showEditMuscleGroupDialog(
                                              context,
                                              group,
                                            ),
                                        icon: const Icon(Icons.edit),
                                        tooltip: 'Rename muscle group',
                                      ),
                                      IconButton(
                                        onPressed: () => showAddExerciseDialog(
                                          context,
                                          group,
                                        ),
                                        icon: const Icon(Icons.fitness_center),
                                        tooltip: 'Add exercise',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (group.exercises.isEmpty)
                                const Text(
                                  'No exercises yet. Tap the dumbbell icon to add one.',
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: group.exercises.map((exercise) {
                                    return Tooltip(
                                      message: 'Edit ${exercise.name}',
                                      child: ActionChip(
                                        label: Text(
                                          '${exercise.name} (${exercise.unit.label})',
                                        ),
                                        onPressed: () => showEditExerciseDialog(
                                          context,
                                          group,
                                          exercise,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (context, _) =>
                        const SizedBox(height: 12),
                    itemCount: groups.length,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({
    required this.title,
    required this.hintText,
    this.initialValue,
    this.confirmLabel = 'Add',
  });

  final String title;
  final String hintText;
  final String? initialValue;
  final String confirmLabel;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      Navigator.of(context).pop(null);
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class _ExerciseDialogResult {
  const _ExerciseDialogResult({required this.name, required this.unit});

  final String name;
  final ExerciseUnit unit;
}

class _ExerciseDialog extends StatefulWidget {
  const _ExerciseDialog({
    required this.groupName,
    this.title = 'New Exercise',
    this.confirmLabel = 'Add',
    this.initialName,
    this.initialUnit,
  });

  final String groupName;
  final String title;
  final String confirmLabel;
  final String? initialName;
  final ExerciseUnit? initialUnit;

  @override
  State<_ExerciseDialog> createState() => _ExerciseDialogState();
}

class _ExerciseDialogState extends State<_ExerciseDialog> {
  late final TextEditingController _controller;
  late ExerciseUnit _selectedUnit;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
    _selectedUnit = widget.initialUnit ?? ExerciseUnit.weightReps;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pop(_ExerciseDialogResult(name: trimmed, unit: _selectedUnit));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: widget.initialName == null
                    ? 'e.g. Bench Press for ${widget.groupName}'
                    : 'Exercise name',
              ),
              onSubmitted: (_) {},
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ExerciseUnit>(
              initialValue: _selectedUnit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: ExerciseUnit.values
                  .map(
                    (unit) => DropdownMenuItem<ExerciseUnit>(
                      value: unit,
                      child: Text(unit.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _selectedUnit = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center, size: 64),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
