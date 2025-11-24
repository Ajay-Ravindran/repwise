import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/exercise.dart';
import '../models/muscle_group.dart';
import '../models/workout.dart';
import '../providers/gym_log_provider.dart';
import '../utils/workout_entry_formatter.dart';
import '../widgets/scrollable_metrics_text.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  static Future<void> showStartExerciseSheet(BuildContext context) async {
    final rootContext = context;
    final provider = rootContext.read<GymLogProvider>();
    final session = provider.activeSession;
    if (session == null) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text('Start a workout before selecting exercises.'),
        ),
      );
      return;
    }
    if (provider.activeExercise != null) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Finish or cancel the current exercise before starting another.',
          ),
        ),
      );
      return;
    }
    final groups = provider.muscleGroups
        .where((group) => group.exercises.isNotEmpty)
        .toList();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text('Add exercises in the library before starting.'),
        ),
      );
      return;
    }

    var selectedGroupId = groups.first.id;
    final Set<String> selectedExerciseIds = <String>{
      if (groups.first.exercises.isNotEmpty) groups.first.exercises.first.id,
    };

    await showModalBottomSheet<void>(
      context: rootContext,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              final group = groups.firstWhere(
                (candidate) => candidate.id == selectedGroupId,
              );
              final exercises = group.exercises;

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add Exercise',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Select a muscle group and one or more exercises to add to your workout. '
                      'Exercises selected together are tracked as a superset.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Muscle group',
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedGroupId,
                          isExpanded: true,
                          items: groups
                              .map(
                                (group) => DropdownMenuItem<String>(
                                  value: group.id,
                                  child: Text(group.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null || value == selectedGroupId) {
                              return;
                            }
                            setState(() {
                              selectedGroupId = value;
                              selectedExerciseIds
                                ..clear()
                                ..addAll(
                                  groups
                                      .firstWhere(
                                        (group) => group.id == selectedGroupId,
                                      )
                                      .exercises
                                      .map((exercise) => exercise.id)
                                      .take(1),
                                );
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (exercises.isEmpty)
                      const Text(
                        'No exercises available for this muscle group yet.',
                      )
                    else
                      Column(
                        children: exercises.map((exercise) {
                          final isSelected = selectedExerciseIds.contains(
                            exercise.id,
                          );
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked ?? false) {
                                  selectedExerciseIds.add(exercise.id);
                                } else {
                                  selectedExerciseIds.remove(exercise.id);
                                }
                              });
                            },
                            title: Text(exercise.name),
                            subtitle: Text(exercise.unit.label),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: selectedExerciseIds.isEmpty
                          ? null
                          : () {
                              final log = provider.startExercise(
                                muscleGroupId: selectedGroupId,
                                exerciseIds: selectedExerciseIds.toList(),
                              );
                              if (log == null) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(
                                    content: Text('Unable to start exercise.'),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(sheetContext).pop();
                              ScaffoldMessenger.of(rootContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    log.isSuperset
                                        ? 'Superset started.'
                                        : 'Exercise started.',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Add Exercise'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Future<void> showAddSetSheet(
    BuildContext context, {
    required WorkoutExerciseLog exerciseLog,
    WorkoutSet? initialSet,
  }) async {
    final rootContext = context;
    final provider = rootContext.read<GymLogProvider>();
    final session = provider.activeSession;
    if (session == null) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(content: Text('Start a workout before logging sets.')),
      );
      return;
    }

    WorkoutExerciseLog? currentExercise;
    for (final log in session.exercises) {
      if (log.id == exerciseLog.id) {
        currentExercise = log;
        break;
      }
    }
    if (currentExercise == null) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(content: Text('This exercise is no longer active.')),
      );
      return;
    }

    final group = provider.muscleGroupById(currentExercise.muscleGroupId);
    if (group == null) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text('Muscle group for this exercise is missing.'),
        ),
      );
      return;
    }

    WorkoutSet? existingSet;
    final bool isEditing = initialSet != null;
    if (isEditing) {
      final targetId = initialSet.id;
      for (final set in currentExercise.sets) {
        if (set.id == targetId) {
          existingSet = set;
          break;
        }
      }
      if (existingSet == null) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          const SnackBar(content: Text('Set is no longer available.')),
        );
        return;
      }
    }

    final List<Exercise> exercises = group.exercises;
    if (exercises.isEmpty) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Add exercises for this muscle group before logging sets.',
          ),
        ),
      );
      return;
    }

    final Map<String, Exercise> exercisesById = <String, Exercise>{
      for (final exercise in exercises) exercise.id: exercise,
    };
    if (currentExercise.exerciseIds.isNotEmpty) {
      for (final id in currentExercise.exerciseIds) {
        final cached = provider.exerciseById(id);
        if (cached != null) {
          exercisesById.putIfAbsent(id, () => cached);
        }
      }
    }

    var draftCounter = 0;
    String nextDraftId() => 'draft_${draftCounter++}';
    final List<_DraftSetEntry> drafts = <_DraftSetEntry>[];

    // Determine which set to use for pre-population
    WorkoutSet? setToPopulateFrom;
    if (isEditing && existingSet != null) {
      setToPopulateFrom = existingSet;
    } else if (!isEditing && currentExercise.sets.isNotEmpty) {
      // Pre-populate from the last set when adding a new set
      setToPopulateFrom = currentExercise.sets.last;
    }

    if (setToPopulateFrom != null) {
      for (final entry in setToPopulateFrom.entries) {
        final draft = _DraftSetEntry(
          id: nextDraftId(),
          exerciseId: entry.exerciseId,
        );
        if (entry.reps != null) {
          draft.reps = entry.reps!.toString();
        }
        if (entry.weight != null) {
          draft.weight = entry.weight!.toString();
        }
        if (entry.distance != null) {
          draft.distance = entry.distance!.toString();
        }
        if (entry.duration != null) {
          draft.time = entry.duration!.inSeconds.toString();
        }
        if (entry.halfReps != null) {
          draft.halfReps = entry.halfReps!.toString();
        }
        if (entry.comment != null) {
          draft.comment = entry.comment!;
        }
        drafts.add(draft);
      }
    } else {
      final List<String> defaultIds = currentExercise.exerciseIds
          .where((id) => exercisesById.containsKey(id))
          .toList();
      if (defaultIds.isEmpty && exercises.isNotEmpty) {
        defaultIds.add(exercises.first.id);
      }
      if (defaultIds.isEmpty) {
        drafts.add(_DraftSetEntry(id: nextDraftId()));
      } else {
        for (final id in defaultIds) {
          drafts.add(_DraftSetEntry(id: nextDraftId(), exerciseId: id));
        }
      }
    }

    String? validationError;

    await showModalBottomSheet<void>(
      context: rootContext,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              Exercise? resolveExercise(String? exerciseId) {
                if (exerciseId == null) {
                  return null;
                }
                return exercisesById[exerciseId] ??
                    provider.exerciseById(exerciseId);
              }

              List<Widget> metricFieldsFor(
                Exercise exercise,
                _DraftSetEntry draft,
              ) {
                Widget buildField({
                  required String label,
                  required String fieldKey,
                  required String initialValue,
                  TextInputType keyboardType =
                      const TextInputType.numberWithOptions(decimal: true),
                  required void Function(String) onChanged,
                }) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextFormField(
                      key: ValueKey('${draft.id}-$fieldKey-${exercise.id}'),
                      initialValue: initialValue,
                      keyboardType: keyboardType,
                      decoration: InputDecoration(
                        labelText: label,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          onChanged(value);
                          validationError = null;
                        });
                      },
                    ),
                  );
                }

                Widget buildCommentField() {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: TextFormField(
                      key: ValueKey('${draft.id}-comment-${exercise.id}'),
                      initialValue: draft.comment,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Comment (optional)',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          draft.comment = value;
                          validationError = null;
                        });
                      },
                    ),
                  );
                }

                Widget buildHalfRepsField() {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: TextFormField(
                        key: ValueKey('${draft.id}-halfReps-${exercise.id}'),
                        initialValue: draft.halfReps,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Half reps',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            draft.halfReps = value;
                            validationError = null;
                          });
                        },
                      ),
                    ),
                  );
                }

                Widget buildRepsRow({required bool allowHalfReps}) {
                  final repsField = buildField(
                    label: 'Reps',
                    fieldKey: 'reps',
                    initialValue: draft.reps,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: false,
                    ),
                    onChanged: (value) => draft.reps = value,
                  );
                  if (!allowHalfReps) {
                    return repsField;
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: repsField),
                      const SizedBox(width: 12),
                      buildHalfRepsField(),
                    ],
                  );
                }

                final List<Widget> fields = <Widget>[];

                switch (exercise.unit) {
                  case ExerciseUnit.weightReps:
                    fields
                      ..add(
                        buildField(
                          label: 'Weight (kg)',
                          fieldKey: 'weight',
                          initialValue: draft.weight,
                          onChanged: (value) => draft.weight = value,
                        ),
                      )
                      ..add(buildRepsRow(allowHalfReps: true));
                    break;
                  case ExerciseUnit.reps:
                    fields.add(buildRepsRow(allowHalfReps: true));
                    break;
                  case ExerciseUnit.time:
                    fields.add(
                      buildField(
                        label: 'Time (seconds)',
                        fieldKey: 'time',
                        initialValue: draft.time,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        onChanged: (value) => draft.time = value,
                      ),
                    );
                    break;
                  case ExerciseUnit.distanceTime:
                    fields
                      ..add(
                        buildField(
                          label: 'Distance (km)',
                          fieldKey: 'distance',
                          initialValue: draft.distance,
                          onChanged: (value) => draft.distance = value,
                        ),
                      )
                      ..add(
                        buildField(
                          label: 'Time (seconds)',
                          fieldKey: 'time',
                          initialValue: draft.time,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          onChanged: (value) => draft.time = value,
                        ),
                      );
                    break;
                  case ExerciseUnit.repsTime:
                    fields
                      ..add(buildRepsRow(allowHalfReps: true))
                      ..add(
                        buildField(
                          label: 'Time (seconds)',
                          fieldKey: 'time',
                          initialValue: draft.time,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          onChanged: (value) => draft.time = value,
                        ),
                      );
                    break;
                  case ExerciseUnit.distance:
                    fields.add(
                      buildField(
                        label: 'Distance (km)',
                        fieldKey: 'distance',
                        initialValue: draft.distance,
                        onChanged: (value) => draft.distance = value,
                      ),
                    );
                    break;
                }

                fields.add(buildCommentField());
                return fields;
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Edit Set' : 'Add Set',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text(group.name)),
                        if (currentExercise!.isSuperset)
                          const Chip(label: Text('Superset')),
                        if (currentExercise.isComplete)
                          const Chip(label: Text('Completed')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...drafts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final draft = entry.value;
                      final exercise = resolveExercise(draft.exerciseId);
                      final bool canRemove = drafts.length > 1;
                      final bool isMissingExercise =
                          draft.exerciseId != null && exercise == null;
                      return Card(
                        key: ValueKey(draft.id),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      drafts.length > 1
                                          ? 'Entry ${index + 1}'
                                          : 'Entry',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                  ),
                                  if (canRemove)
                                    IconButton(
                                      tooltip: 'Remove',
                                      onPressed: () {
                                        setState(() {
                                          drafts.remove(draft);
                                          validationError = null;
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                ],
                              ),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Exercise',
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: draft.exerciseId,
                                    isExpanded: true,
                                    hint: const Text('Select exercise'),
                                    items: exercises
                                        .map(
                                          (exercise) =>
                                              DropdownMenuItem<String>(
                                                value: exercise.id,
                                                child: Text(exercise.name),
                                              ),
                                        )
                                        .toList(),
                                    onChanged: (selected) {
                                      if (selected == null) {
                                        return;
                                      }
                                      setState(() {
                                        draft.exerciseId = selected;
                                        draft.reps = '';
                                        draft.weight = '';
                                        draft.distance = '';
                                        draft.time = '';
                                        draft.halfReps = '';
                                        draft.comment = '';
                                        validationError = null;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              if (isMissingExercise)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'This exercise is no longer available. Choose another to continue.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                  ),
                                ),
                              if (exercise != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        exercise.unit.label,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      ...metricFieldsFor(exercise, draft),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          final _DraftSetEntry newEntry = _DraftSetEntry(
                            id: nextDraftId(),
                          );
                          if (drafts.isNotEmpty) {
                            newEntry.exerciseId = drafts.last.exerciseId;
                          } else if (exercises.isNotEmpty) {
                            newEntry.exerciseId = exercises.first.id;
                          }
                          drafts.add(newEntry);
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add another exercise entry'),
                    ),
                    if (validationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          validationError!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        void showError(String message) {
                          setState(() {
                            validationError = message;
                          });
                        }

                        int? parsePositiveInt(String value) {
                          final trimmed = value.trim();
                          if (trimmed.isEmpty) {
                            return null;
                          }
                          final parsed = int.tryParse(trimmed);
                          if (parsed == null || parsed <= 0) {
                            return null;
                          }
                          return parsed;
                        }

                        double? parsePositiveDouble(String value) {
                          final trimmed = value.trim();
                          if (trimmed.isEmpty) {
                            return null;
                          }
                          final parsed = double.tryParse(trimmed);
                          if (parsed == null || parsed <= 0) {
                            return null;
                          }
                          return parsed;
                        }

                        Duration? parsePositiveDuration(String value) {
                          final seconds = parsePositiveInt(value);
                          if (seconds == null) {
                            return null;
                          }
                          return Duration(seconds: seconds);
                        }

                        if (drafts.isEmpty) {
                          showError('Add at least one exercise entry.');
                          return;
                        }

                        final List<WorkoutSetEntry> entries =
                            <WorkoutSetEntry>[];

                        for (final draft in drafts) {
                          final exerciseId = draft.exerciseId;
                          if (exerciseId == null) {
                            showError('Select an exercise for each entry.');
                            return;
                          }
                          final exercise = resolveExercise(exerciseId);
                          if (exercise == null) {
                            showError('Selected exercise is unavailable.');
                            return;
                          }

                          int? reps;
                          double? weight;
                          double? distance;
                          Duration? duration;
                          int? halfReps;

                          final bool allowHalfReps =
                              exercise.unit == ExerciseUnit.weightReps ||
                              exercise.unit == ExerciseUnit.reps ||
                              exercise.unit == ExerciseUnit.repsTime;

                          final String halfRepsInput = draft.halfReps.trim();
                          if (halfRepsInput.isNotEmpty) {
                            final parsedHalfReps = int.tryParse(halfRepsInput);
                            if (parsedHalfReps == null || parsedHalfReps < 0) {
                              showError(
                                'Enter a valid half rep count for ${exercise.name}.',
                              );
                              return;
                            }
                            if (!allowHalfReps) {
                              showError(
                                'Half reps are only valid for weight & reps, reps, or reps & time exercises.',
                              );
                              return;
                            }
                            if (parsedHalfReps > 0) {
                              halfReps = parsedHalfReps;
                            }
                          }

                          switch (exercise.unit) {
                            case ExerciseUnit.weightReps:
                              weight = parsePositiveDouble(draft.weight);
                              reps = parsePositiveInt(draft.reps);
                              if (weight == null || reps == null) {
                                showError(
                                  'Enter weight and reps for ${exercise.name}.',
                                );
                                return;
                              }
                              break;
                            case ExerciseUnit.reps:
                              reps = parsePositiveInt(draft.reps);
                              if (reps == null) {
                                showError('Enter reps for ${exercise.name}.');
                                return;
                              }
                              break;
                            case ExerciseUnit.time:
                              duration = parsePositiveDuration(draft.time);
                              if (duration == null) {
                                showError('Enter time for ${exercise.name}.');
                                return;
                              }
                              break;
                            case ExerciseUnit.distanceTime:
                              distance = parsePositiveDouble(draft.distance);
                              duration = parsePositiveDuration(draft.time);
                              if (distance == null || duration == null) {
                                showError(
                                  'Enter distance and time for ${exercise.name}.',
                                );
                                return;
                              }
                              break;
                            case ExerciseUnit.repsTime:
                              reps = parsePositiveInt(draft.reps);
                              duration = parsePositiveDuration(draft.time);
                              if (reps == null || duration == null) {
                                showError(
                                  'Enter reps and time for ${exercise.name}.',
                                );
                                return;
                              }
                              break;
                            case ExerciseUnit.distance:
                              distance = parsePositiveDouble(draft.distance);
                              if (distance == null) {
                                showError(
                                  'Enter distance for ${exercise.name}.',
                                );
                                return;
                              }
                              break;
                          }

                          final String trimmedComment = draft.comment.trim();

                          entries.add(
                            WorkoutSetEntry(
                              exerciseId: exerciseId,
                              unit: exercise.unit,
                              reps: reps,
                              weight: weight,
                              distance: distance,
                              duration: duration,
                              halfReps: halfReps,
                              comment: trimmedComment.isEmpty
                                  ? null
                                  : trimmedComment,
                            ),
                          );
                        }

                        final bool success;
                        if (isEditing) {
                          final updateId = existingSet?.id;
                          if (updateId == null) {
                            showError('Unable to update this set.');
                            return;
                          }
                          success = provider.updateSetInExercise(
                            exerciseLogId: currentExercise!.id,
                            setId: updateId,
                            entries: entries,
                          );
                        } else {
                          success = provider.addSetToExercise(
                            exerciseLogId: currentExercise!.id,
                            entries: entries,
                          );
                        }
                        if (!success) {
                          showError(
                            isEditing
                                ? 'Unable to update this set.'
                                : 'Unable to add this set.',
                          );
                          return;
                        }

                        Navigator.of(sheetContext).pop();
                        ScaffoldMessenger.of(rootContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              isEditing ? 'Set updated.' : 'Set added.',
                            ),
                          ),
                        );
                      },
                      icon: Icon(isEditing ? Icons.save : Icons.check),
                      label: Text(isEditing ? 'Update Set' : 'Add Set'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _DraftSetEntry {
  _DraftSetEntry({required this.id, this.exerciseId});

  final String id;
  String? exerciseId;
  String reps = '';
  String weight = '';
  String distance = '';
  String time = '';
  String halfReps = '';
  String comment = '';
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late final AudioPlayer _audioPlayer;
  Uint8List? _toneBytes;
  int _lastCompletionSignalId = 0;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
  }

  @override
  void dispose() {
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  void _maybeHandleTimerCompletion(GymLogProvider provider) {
    final completionId = provider.timerCompletionId;
    if (completionId == _lastCompletionSignalId) {
      return;
    }
    _lastCompletionSignalId = completionId;
    if (completionId == 0) {
      return;
    }
    if (!provider.timerSoundEnabled && !provider.timerVibrationEnabled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_playCompletionCue(provider));
    });
  }

  Future<void> _playCompletionCue(GymLogProvider provider) async {
    if (provider.timerSoundEnabled) {
      final bytes = _toneBytes ??= _createGentleTone();
      try {
        await _audioPlayer.stop();
        await _audioPlayer.play(BytesSource(bytes), volume: 0.6);
      } catch (_) {
        // Ignore playback errors to avoid interrupting the UI flow.
      }
    }
    if (provider.timerVibrationEnabled) {
      try {
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.lightImpact();
      } catch (_) {
        // Device might not support the requested haptic feedback.
      }
    }
  }

  Uint8List _createGentleTone() {
    const sampleRate = 44100;
    const frequency = 660.0;
    const durationSeconds = 0.9;
    final totalSamples = (sampleRate * durationSeconds).round();
    final samples = Int16List(totalSamples);
    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final envelope = 1 - (i / totalSamples);
      final value = math.sin(2 * math.pi * frequency * t) * envelope * 0.35;
      final sample = (value * 32767).round().clamp(-32768, 32767);
      samples[i] = sample;
    }
    return _wrapAsWav(samples, sampleRate);
  }

  Uint8List _wrapAsWav(Int16List samples, int sampleRate) {
    final bytes = Uint8List(44 + samples.lengthInBytes);
    final byteData = ByteData.view(bytes.buffer);
    byteData.setUint32(0, 0x46464952, Endian.little); // 'RIFF'
    byteData.setUint32(4, bytes.length - 8, Endian.little);
    byteData.setUint32(8, 0x45564157, Endian.little); // 'WAVE'
    byteData.setUint32(12, 0x20746D66, Endian.little); // 'fmt '
    byteData.setUint32(16, 16, Endian.little); // PCM header size
    byteData.setUint16(20, 1, Endian.little); // audio format (PCM)
    byteData.setUint16(22, 1, Endian.little); // channels
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    byteData.setUint16(32, 2, Endian.little); // block align
    byteData.setUint16(34, 16, Endian.little); // bits per sample
    byteData.setUint32(36, 0x61746164, Endian.little); // 'data'
    byteData.setUint32(40, samples.lengthInBytes, Endian.little);
    bytes.setAll(44, samples.buffer.asUint8List());
    return bytes;
  }

  Future<void> _showTimerSetupSheet(BuildContext context) async {
    final provider = context.read<GymLogProvider>();
    final existing = provider.timerTotalDuration ?? Duration.zero;

    final result = await showModalBottomSheet<_TimerSetupResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: _TimerSetupSheet(
            initialDuration: existing,
            initialSoundEnabled: provider.timerSoundEnabled,
            initialVibrationEnabled: provider.timerVibrationEnabled,
          ),
        );
      },
    );

    if (result != null) {
      provider.startTimer(
        duration: result.duration,
        enableSound: result.soundEnabled,
        enableVibration: result.vibrationEnabled,
      );
    }
  }

  Future<void> _showTimerPopup(BuildContext context) async {
    final rootContext = context;
    await showDialog<void>(
      context: rootContext,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Consumer<GymLogProvider>(
                  builder: (ctx, provider, _) {
                    return _buildTimerDialogContent(
                      ctx,
                      provider,
                      onClose: () => Navigator.of(dialogContext).pop(),
                      onOpenSetup: () {
                        Navigator.of(dialogContext).pop();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) {
                            return;
                          }
                          _showTimerSetupSheet(rootContext);
                        });
                        return Future<void>.value();
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimerDialogContent(
    BuildContext context,
    GymLogProvider provider, {
    required VoidCallback onClose,
    required Future<void> Function() onOpenSetup,
  }) {
    final theme = Theme.of(context);

    if (!provider.isTimerActive) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Workout Timer', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Keep rest periods on track with a quick countdown.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              unawaited(onOpenSetup());
            },
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Start Timer'),
          ),
        ],
      );
    }

    final total = provider.timerTotalDuration ?? Duration.zero;
    final remaining = provider.timerRemaining ?? total;
    final elapsed = provider.timerElapsed ?? Duration.zero;
    final isRunning = provider.isTimerRunning;
    final isComplete = provider.isTimerComplete;
    final progress = total.inMilliseconds == 0
        ? 1.0
        : (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final clock = _formatClock(remaining);

    VoidCallback? primaryAction;
    IconData primaryIcon;
    String primaryLabel;
    if (isComplete) {
      primaryIcon = Icons.restart_alt;
      primaryLabel = 'Restart';
      primaryAction = total.inSeconds > 0 ? provider.restartTimer : null;
    } else if (isRunning) {
      primaryIcon = Icons.pause;
      primaryLabel = 'Pause';
      primaryAction = provider.pauseTimer;
    } else {
      primaryIcon = Icons.play_arrow;
      primaryLabel = 'Resume';
      primaryAction = remaining.inSeconds > 0 ? provider.resumeTimer : null;
    }

    final secondaryLabel = isComplete ? 'Dismiss' : 'Stop';
    final secondaryIcon = isComplete ? Icons.clear : Icons.stop;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Workout Timer', style: theme.textTheme.titleMedium),
            if (isComplete) ...[
              const SizedBox(width: 8),
              const Chip(label: Text('Complete')),
            ],
            const Spacer(),
            IconButton(
              tooltip: 'Set new timer',
              onPressed: () {
                unawaited(onOpenSetup());
              },
              icon: const Icon(Icons.timer_outlined),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            clock,
            style:
                theme.textTheme.displayMedium ?? theme.textTheme.headlineLarge,
          ),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: isComplete ? 1 : progress),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Play sound on completion'),
          value: provider.timerSoundEnabled,
          onChanged: (value) =>
              provider.updateTimerPreferences(soundEnabled: value),
        ),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Vibrate on completion'),
          value: provider.timerVibrationEnabled,
          onChanged: (value) =>
              provider.updateTimerPreferences(vibrationEnabled: value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: primaryAction,
              icon: Icon(primaryIcon),
              label: Text(primaryLabel),
            ),
            OutlinedButton.icon(
              onPressed: () {
                provider.dismissTimer();
              },
              icon: Icon(secondaryIcon),
              label: Text(secondaryLabel),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GymLogProvider>();
    _maybeHandleTimerCompletion(provider);
    final session = provider.activeSession;
    final groupsById = {
      for (final group in provider.muscleGroups) group.id: group,
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, provider, session),
          const SizedBox(height: 16),
          if (provider.muscleGroups.isEmpty)
            const Expanded(
              child: _EmptyState(
                message:
                    'Add muscle groups and exercises before starting a workout.',
              ),
            )
          else if (session == null)
            const Expanded(
              child: _EmptyState(
                message: 'Tap Start to begin logging your workout.',
              ),
            )
          else
            Expanded(
              child: _buildActiveWorkoutBody(
                context,
                provider,
                session,
                groupsById,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    GymLogProvider provider,
    WorkoutSession? session,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text('Workout', style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(width: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (provider.isTimerActive)
              _TimerBadge(
                label: _formatClock(provider.timerRemaining ?? Duration.zero),
              ),
            IconButton(
              tooltip: provider.isTimerActive ? 'View timer' : 'Start timer',
              onPressed: () => _showTimerPopup(context),
              icon: Icon(
                provider.isTimerActive ? Icons.timer : Icons.timer_outlined,
              ),
            ),
            if (session == null)
              FilledButton(
                onPressed: provider.muscleGroups.isEmpty
                    ? null
                    : () => _handleStartWorkout(context, provider),
                child: const Text('Start Workout'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveWorkoutBody(
    BuildContext context,
    GymLogProvider provider,
    WorkoutSession session,
    Map<String, MuscleGroup> groupsById,
  ) {
    final exercises = session.exercises;
    final activeExercise = provider.activeExercise;
    final hasLoggedSets = exercises.any((exercise) => exercise.sets.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Active workout',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Started at ${_formatTime(session.startedAt)}'),
                if (activeExercise != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Logging: ${_exerciseNamesFor(activeExercise, provider).join(', ')}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                activeExercise == null
                    ? 'Add an exercise to begin logging sets.'
                    : 'Add sets or finish the active exercise below.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: activeExercise == null
                  ? () => WorkoutScreen.showStartExerciseSheet(context)
                  : () => WorkoutScreen.showAddSetSheet(
                      context,
                      exerciseLog: activeExercise,
                    ),
              icon: Icon(
                activeExercise == null ? Icons.playlist_add : Icons.add,
              ),
              label: Text(activeExercise == null ? 'Add Exercise' : 'Add Set'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: exercises.isEmpty
              ? const _EmptyState(message: 'Add an exercise to log sets.')
              : ListView.separated(
                  itemCount: exercises.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final log = exercises[index];
                    return _buildExerciseCard(
                      context,
                      provider,
                      log,
                      groupsById,
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: hasLoggedSets
              ? () => _handleFinishWorkout(context, provider)
              : null,
          child: const Text('Finish Workout'),
        ),
      ],
    );
  }

  Widget _buildExerciseCard(
    BuildContext context,
    GymLogProvider provider,
    WorkoutExerciseLog log,
    Map<String, MuscleGroup> groupsById,
  ) {
    final muscleGroup = groupsById[log.muscleGroupId];
    final exerciseNames = _exerciseNamesFor(log, provider);
    final isActive = provider.activeExercise?.id == log.id && !log.isComplete;
    final hasSets = log.sets.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        muscleGroup?.name ?? 'Exercise',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: exerciseNames
                            .map((name) => Chip(label: Text(name)))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (log.isSuperset) const Chip(label: Text('Superset')),
                    if (log.isComplete)
                      const Chip(label: Text('Completed'))
                    else if (isActive)
                      const Chip(label: Text('Active')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSetsList(context, provider, log),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (!log.isComplete)
                  FilledButton.icon(
                    onPressed: () => WorkoutScreen.showAddSetSheet(
                      context,
                      exerciseLog: log,
                    ),
                    icon: const Icon(Icons.fitness_center),
                    label: const Text('Add Set'),
                  ),
                if (!log.isComplete && hasSets)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _handleFinishExercise(context, provider, log),
                    icon: const Icon(Icons.check),
                    label: const Text('Finish Exercise'),
                  ),
                if (!log.isComplete && !hasSets)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _handleCancelExercise(context, provider, log),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel Exercise'),
                  ),
                if (log.isComplete)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _handleReopenExercise(context, provider, log),
                    icon: const Icon(Icons.replay),
                    label: const Text('Reopen'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetsList(
    BuildContext context,
    GymLogProvider provider,
    WorkoutExerciseLog log,
  ) {
    if (log.sets.isEmpty) {
      return const Text('No sets logged yet.');
    }

    return ReorderableListView.builder(
      key: ValueKey('sets-${log.id}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: log.sets.length,
      onReorder: (oldIndex, newIndex) {
        final moved = provider.reorderSetsInExercise(
          exerciseLogId: log.id,
          oldIndex: oldIndex,
          newIndex: newIndex,
        );
        if (!moved && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to reorder sets.')),
          );
        }
      },
      itemBuilder: (context, index) {
        final set = log.sets[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(set.id),
          index: index,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Set ${index + 1} · ${_formatSetTimestamp(set.timestamp)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      // Check if this set is a PR
                      if (set.entries.length == 1 && set.entries.isNotEmpty)
                        Builder(
                          builder: (context) {
                            final isPR = provider.isPersonalRecord(set.entries.first, set);
                            if (isPR) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.emoji_events,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      IconButton(
                        tooltip: 'Edit set',
                        onPressed: () => WorkoutScreen.showAddSetSheet(
                          context,
                          exerciseLog: log,
                          initialSet: set,
                        ),
                        icon: const Icon(Icons.edit),
                      ),
                      IconButton(
                        tooltip: 'Delete set',
                        onPressed: () =>
                            _handleRemoveSet(context, provider, log, set),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: set.entries.map((entry) {
                      final exercise =
                          provider.exerciseById(entry.exerciseId) ??
                          Exercise(
                            id: entry.exerciseId,
                            name: 'Exercise',
                            unit: entry.unit,
                          );
                      return _SetRow(
                        exercise: exercise,
                        entry: entry,
                        isSuperset: set.entries.length > 1,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<String> _exerciseNamesFor(
    WorkoutExerciseLog log,
    GymLogProvider provider,
  ) {
    final ids = <String>{...log.exerciseIds};
    for (final set in log.sets) {
      for (final entry in set.entries) {
        ids.add(entry.exerciseId);
      }
    }
    final names = <String>[];
    for (final id in ids) {
      final exercise = provider.exerciseById(id);
      if (exercise != null) {
        names.add(exercise.name);
      }
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  void _handleStartWorkout(BuildContext context, GymLogProvider provider) {
    provider.startWorkout();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Workout started.')));
  }

  void _handleFinishWorkout(BuildContext context, GymLogProvider provider) {
    provider.finishWorkout();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Workout saved.')));
  }

  void _handleFinishExercise(
    BuildContext context,
    GymLogProvider provider,
    WorkoutExerciseLog log,
  ) {
    final success = provider.completeExercise(log.id);
    _showSnackBar(
      context,
      success ? 'Exercise finished.' : 'Unable to finish this exercise.',
    );
  }

  void _handleCancelExercise(
    BuildContext context,
    GymLogProvider provider,
    WorkoutExerciseLog log,
  ) {
    final success = provider.cancelExercise(log.id);
    _showSnackBar(
      context,
      success ? 'Exercise cancelled.' : 'Unable to cancel this exercise.',
    );
  }

  void _handleReopenExercise(
    BuildContext context,
    GymLogProvider provider,
    WorkoutExerciseLog log,
  ) {
    final success = provider.reopenExercise(log.id);
    _showSnackBar(
      context,
      success ? 'Exercise reopened.' : 'Unable to reopen this exercise.',
    );
  }

  void _handleRemoveSet(
    BuildContext context,
    GymLogProvider provider,
    WorkoutExerciseLog log,
    WorkoutSet set,
  ) {
    final success = provider.removeSetFromExercise(
      exerciseLogId: log.id,
      setId: set.id,
    );
    _showSnackBar(
      context,
      success ? 'Set removed.' : 'Unable to remove this set.',
    );
  }

  String _formatSetTimestamp(DateTime timestamp) => _formatTime(timestamp);

  void _showSnackBar(BuildContext context, String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  // ignore: no_logic_in_create_state
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  String _formatClock(Duration duration) {
    final totalSeconds = math.max(0, math.min(duration.inSeconds, 359999));
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}

class _TimerSetupResult {
  const _TimerSetupResult({
    required this.duration,
    required this.soundEnabled,
    required this.vibrationEnabled,
  });

  final Duration duration;
  final bool soundEnabled;
  final bool vibrationEnabled;
}

class _TimerBadge extends StatelessWidget {
  const _TimerBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
    );
  }
}

class _TimerSetupSheet extends StatefulWidget {
  const _TimerSetupSheet({
    required this.initialDuration,
    required this.initialSoundEnabled,
    required this.initialVibrationEnabled,
  });

  final Duration initialDuration;
  final bool initialSoundEnabled;
  final bool initialVibrationEnabled;

  @override
  State<_TimerSetupSheet> createState() => _TimerSetupSheetState();
}

class _TimerSetupSheetState extends State<_TimerSetupSheet> {
  late final TextEditingController _minutesController;
  late final TextEditingController _secondsController;
  late bool _soundEnabled;
  late bool _vibrationEnabled;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final minutes = widget.initialDuration.inMinutes;
    final secondsRemainder = widget.initialDuration.inSeconds % 60;
    _minutesController = TextEditingController(
      text: minutes > 0 ? minutes.toString() : '',
    );
    _secondsController = TextEditingController(
      text: secondsRemainder > 0
          ? secondsRemainder.toString().padLeft(2, '0')
          : '',
    );
    _soundEnabled = widget.initialSoundEnabled;
    _vibrationEnabled = widget.initialVibrationEnabled;
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    final seconds = int.tryParse(_secondsController.text.trim()) ?? 0;
    if (minutes < 0 || seconds < 0) {
      setState(
        () => _errorMessage = 'Please enter non-negative values for the timer.',
      );
      return;
    }
    if (seconds >= 60) {
      setState(() => _errorMessage = 'Seconds must be less than 60.');
      return;
    }
    final duration = Duration(minutes: minutes, seconds: seconds);
    if (duration.inSeconds <= 0) {
      setState(() => _errorMessage = 'Set a duration longer than zero.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _TimerSetupResult(
        duration: duration,
        soundEnabled: _soundEnabled,
        vibrationEnabled: _vibrationEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Start Timer', style: theme.textTheme.titleLarge),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minutesController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Minutes',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _secondsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Seconds',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Play sound on completion'),
          value: _soundEnabled,
          onChanged: (value) {
            setState(() => _soundEnabled = value);
          },
        ),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Vibrate on completion'),
          value: _vibrationEnabled,
          onChanged: (value) {
            setState(() => _vibrationEnabled = value);
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.timer_outlined),
          label: const Text('Start Timer'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message, textAlign: TextAlign.center));
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.exercise,
    required this.entry,
    this.isSuperset = false,
  });

  final Exercise exercise;
  final WorkoutSetEntry entry;
  final bool isSuperset;

  @override
  Widget build(BuildContext context) {
    final metrics = formatWorkoutEntry(entry);
    final hasComment = (entry.comment?.trim().isNotEmpty ?? false);

    void showCommentDialog() {
      final commentText = entry.comment?.trim();
      if (commentText == null || commentText.isEmpty) {
        return;
      }
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Comment for ${exercise.name}'),
            content: Text(commentText),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 24,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isSuperset)
              SizedBox(
                width: 100,
                child: Text(
                  exercise.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  exercise.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(child: ScrollableMetricsText(text: metrics)),
            if (hasComment)
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  tooltip: 'View comment',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minHeight: 28,
                    minWidth: 28,
                  ),
                  splashRadius: 18,
                  iconSize: 18,
                  onPressed: showCommentDialog,
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
