import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/exercise.dart';
import '../models/muscle_group.dart';
import '../models/workout.dart';
import '../providers/gym_log_provider.dart';
import '../utils/workout_entry_formatter.dart';
import '../widgets/scrollable_metrics_text.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  static final List<Color> _palette = <Color>[
    const Color(0xFF80CBC4),
    const Color(0xFFFFAB91),
    const Color(0xFFAED581),
    const Color(0xFF81D4FA),
    const Color(0xFFF48FB1),
    const Color(0xFFFFF176),
    const Color(0xFFE6EE9C),
    const Color(0xFFCE93D8),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDay = DateTime(now.year, now.month, now.day);
    _selectedDay = _focusedDay;
  }

  Future<void> _exportLogs(BuildContext context) async {
    final provider = context.read<GymLogProvider>();
    final file = await provider.createExportFile();
    if (!context.mounted) {
      return;
    }
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to export logs right now.')),
      );
      return;
    }
    final segments = file.path.split(Platform.pathSeparator);
    final fileName = segments.isNotEmpty
        ? segments.last
        : 'gym-log-export.json';
    try {
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'application/json', name: fileName)],
        text:
            'Gym Log export — import this file from the History tab on another device.',
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sharing failed.')));
    }
  }

  Future<void> _importLogs(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (!context.mounted) {
      return;
    }
    if (result == null || result.files.isEmpty) {
      return;
    }
    final path = result.files.single.path;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected file is not accessible.')),
      );
      return;
    }
    final provider = context.read<GymLogProvider>();
    final success = await provider.importFromFile(File(path));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Logs imported successfully.'
              : 'Could not import the selected file.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GymLogProvider>();
    final selectedDay = _selectedDay ?? _focusedDay;
    final sessionsForSelectedDay = provider.sessionsForDay(selectedDay);

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('History', style: Theme.of(context).textTheme.titleLarge),
            PopupMenuButton<_HistoryAction>(
              tooltip: 'History options',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                switch (action) {
                  case _HistoryAction.export:
                    _exportLogs(context);
                    break;
                  case _HistoryAction.import:
                    _importLogs(context);
                    break;
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<_HistoryAction>>[
                PopupMenuItem<_HistoryAction>(
                  value: _HistoryAction.export,
                  child: Row(
                    children: const [
                      Icon(Icons.file_upload_outlined),
                      SizedBox(width: 12),
                      Text('Export logs'),
                    ],
                  ),
                ),
                PopupMenuItem<_HistoryAction>(
                  value: _HistoryAction.import,
                  child: Row(
                    children: const [
                      Icon(Icons.file_download_outlined),
                      SizedBox(width: 12),
                      Text('Import logs'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      SliverToBoxAdapter(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: TableCalendar<WorkoutSession>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.monday,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Color(0xFF26A69A),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Color(0xFF00897B),
                shape: BoxShape.circle,
              ),
            ),
            eventLoader: (day) => provider.sessionsForDay(day),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = DateTime(
                  selected.year,
                  selected.month,
                  selected.day,
                );
                _focusedDay = focused;
              });
            },
            onPageChanged: (focused) => _focusedDay = focused,
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                if (events.isEmpty) {
                  return const SizedBox.shrink();
                }
                final muscleNames = _muscleGroupsForEvents(
                  events.cast<WorkoutSession>(),
                  provider,
                ).toList(growable: false);
                if (muscleNames.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 2,
                      runSpacing: 2,
                      children: muscleNames
                          .take(4)
                          .map(
                            (name) => Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _colorForName(name),
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ];

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
    slivers.add(
      SliverToBoxAdapter(
        child: _SelectedDaySummary(
          day: selectedDay,
          muscleGroupNames: _muscleGroupsForEvents(
            sessionsForSelectedDay,
            provider,
          ).toList(growable: false),
        ),
      ),
    );
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));

    if (sessionsForSelectedDay.isEmpty) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyHistoryState(
            message:
                'No workouts logged for this day. Finish a workout to see it here.',
          ),
        ),
      );
    }
    if (sessionsForSelectedDay.isNotEmpty) {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final session = sessionsForSelectedDay[index];
            final bottomPadding = index == sessionsForSelectedDay.length - 1
                ? 0.0
                : 12.0;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: _SessionCard(
                session: session,
                provider: provider,
                paletteResolver: _colorForName,
              ),
            );
          }, childCount: sessionsForSelectedDay.length),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomScrollView(slivers: slivers),
    );
  }

  Set<String> _muscleGroupsForEvents(
    Iterable<WorkoutSession> sessions,
    GymLogProvider provider,
  ) {
    final Set<String> names = <String>{};
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        final MuscleGroup? group = provider.muscleGroupById(
          exercise.muscleGroupId,
        );
        if (group != null && exercise.hasSets) {
          names.add(group.name);
        }
      }
    }
    return names;
  }

  static Color _colorForName(String name) {
    final normalized = name.toLowerCase();
    final hash = normalized.codeUnits.fold<int>(0, (prev, unit) => prev + unit);
    return _palette[hash % _palette.length];
  }
}

enum _HistoryAction { export, import }

class _SelectedDaySummary extends StatelessWidget {
  const _SelectedDaySummary({
    required this.day,
    required this.muscleGroupNames,
  });

  final DateTime day;
  final List<String> muscleGroupNames;

  @override
  Widget build(BuildContext context) {
    final formatted = _formatDate(day);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(formatted, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (muscleGroupNames.isEmpty)
              const Text('No muscle groups logged.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: muscleGroupNames
                    .map(
                      (name) => Chip(
                        avatar: CircleAvatar(
                          backgroundColor: _HistoryScreenState._colorForName(
                            name,
                          ),
                        ),
                        label: Text(name),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime day) {
    final month = _monthName(day.month);
    final weekday = _weekdayName(day.weekday);
    return '$weekday, $month ${day.day}, ${day.year}';
  }

  static String _monthName(int month) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  static String _weekdayName(int weekday) {
    const days = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[(weekday - 1) % days.length];
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.provider,
    required this.paletteResolver,
  });

  final WorkoutSession session;
  final GymLogProvider provider;
  final Color Function(String) paletteResolver;

  @override
  Widget build(BuildContext context) {
    final groupsById = <String, MuscleGroup?>{
      for (final exercise in session.exercises)
        exercise.muscleGroupId: provider.muscleGroupById(
          exercise.muscleGroupId,
        ),
    };
    final totalSets = session.exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.sets.length,
    );
    final completedExercises = session.exercises
        .where((exercise) => exercise.hasSets)
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Workout at ${_formatTime(session.startedAt)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '$totalSets set${totalSets == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Workout options',
                  onPressed: totalSets == 0
                      ? null
                      : () => _showSetOptions(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (completedExercises.isEmpty)
              const Text('No sets logged for this workout.')
            else
              ..._buildExercisesList(context, completedExercises, groupsById),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  List<Widget> _buildExercisesList(
    BuildContext context,
    List<WorkoutExerciseLog> exercises,
    Map<String, MuscleGroup?> groupsById,
  ) {
    final widgets = <Widget>[];
    String? lastMuscleGroupId;

    for (var i = 0; i < exercises.length; i++) {
      final log = exercises[i];
      final muscleGroup = groupsById[log.muscleGroupId];

      // Add muscle group header if it's different from the last one
      if (log.muscleGroupId != lastMuscleGroupId) {
        if (lastMuscleGroupId != null) {
          widgets.add(const SizedBox(height: 16));
        }
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: muscleGroup != null
                        ? paletteResolver(muscleGroup.name)
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  muscleGroup?.name ?? 'Exercise',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
        lastMuscleGroupId = log.muscleGroupId;
      }

      widgets.add(
        _ExerciseHistorySection(
          log: log,
          provider: provider,
          showMuscleGroup: false,
        ),
      );

      if (i < exercises.length - 1) {
        widgets.add(const SizedBox(height: 12));
      }
    }

    return widgets;
  }

  void _showSetOptions(BuildContext context) {
    final setRefs = _completedSetReferences();
    if (setRefs.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Delete a set',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                ...setRefs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final reference = entry.value;
                  final summary = _setSummary(reference.set);
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text('${index + 1}'),
                    ),
                    title: Text('Set ${index + 1}'),
                    subtitle: summary == null ? null : Text(summary),
                    trailing: const Icon(Icons.delete_outline),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmDeleteSet(context, reference);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _setSummary(WorkoutSet set) {
    if (set.entries.isEmpty) {
      return null;
    }
    final names = set.entries
        .map(
          (entry) =>
              provider.exerciseById(entry.exerciseId)?.name ?? 'Exercise',
        )
        .toList();
    if (names.isEmpty) {
      return null;
    }
    if (names.length == 1) {
      return names.first;
    }
    return '${names.take(2).join(', ')}${names.length > 2 ? '…' : ''}';
  }

  Future<void> _confirmDeleteSet(
    BuildContext context,
    _CompletedSetReference reference,
  ) async {
    final theme = Theme.of(context);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete set?'),
          content: const Text(
            'This will remove the set from your history. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Cancel', style: theme.textTheme.labelLarge),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !context.mounted) {
      return;
    }
    final removed = provider.removeCompletedSet(
      sessionId: session.id,
      exerciseLogId: reference.exercise.id,
      setId: reference.set.id,
    );
    if (!removed && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to delete set.')));
    }
  }

  List<_CompletedSetReference> _completedSetReferences() {
    final refs = <_CompletedSetReference>[];
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        refs.add(_CompletedSetReference(exercise: exercise, set: set));
      }
    }
    refs.sort((a, b) => a.set.timestamp.compareTo(b.set.timestamp));
    return refs;
  }
}

class _ExerciseHistorySection extends StatelessWidget {
  const _ExerciseHistorySection({
    required this.log,
    required this.provider,
    this.showMuscleGroup = true,
  });

  final WorkoutExerciseLog log;
  final GymLogProvider provider;
  final bool showMuscleGroup;

  @override
  Widget build(BuildContext context) {
    final exerciseNames = _exerciseNames();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!log.isSuperset) ...[
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...exerciseNames.map((name) => Chip(label: Text(name))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (log.isSuperset) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Chip(label: Text('Superset')),
          ),
        ],
        if (log.sets.isEmpty)
          const Text('No sets logged for this exercise.')
        else
          Column(
            children: [
              for (var i = 0; i < log.sets.length; i++)
                _WorkoutSetTile(
                  set: log.sets[i],
                  setNumber: i + 1,
                  provider: provider,
                ),
            ],
          ),
      ],
    );
  }

  List<String> _exerciseNames() {
    final ids = <String>{...log.exerciseIds};
    for (final set in log.sets) {
      for (final entry in set.entries) {
        ids.add(entry.exerciseId);
      }
    }
    final names = ids
        .map((id) => provider.exerciseById(id)?.name ?? 'Exercise')
        .toList(growable: false);
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }
}

class _CompletedSetReference {
  const _CompletedSetReference({required this.exercise, required this.set});

  final WorkoutExerciseLog exercise;
  final WorkoutSet set;
}

class _WorkoutSetTile extends StatelessWidget {
  const _WorkoutSetTile({
    required this.set,
    required this.setNumber,
    required this.provider,
  });

  final WorkoutSet set;
  final int setNumber;
  final GymLogProvider provider;

  @override
  Widget build(BuildContext context) {
    final MuscleGroup? group = provider.muscleGroupById(set.muscleGroupId);
    final theme = Theme.of(context);

    void showCommentDialog(String exerciseName, String comment) {
      final trimmed = comment.trim();
      if (trimmed.isEmpty) {
        return;
      }
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Comment for $exerciseName'),
            content: Text(trimmed),
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

    // Build entry widgets based on whether it's a superset or single exercise
    final List<Widget> entryWidgets = <Widget>[];

    // Check if this set holds any current PRs (only for single-exercise sets)
    final currentPRs = set.entries.length == 1 && set.entries.isNotEmpty
        ? provider.getCurrentPRs(set.entries.first.exerciseId)
        : <String>{};
    final isPRSet = currentPRs.contains(set.id);

    for (var i = 0; i < set.entries.length; i++) {
      final entry = set.entries[i];
      final exercise =
          provider.exerciseById(entry.exerciseId) ??
          group?.exercises.firstWhere(
            (exercise) => exercise.id == entry.exerciseId,
            orElse: () => Exercise(
              id: entry.exerciseId,
              name: 'Exercise',
              unit: ExerciseUnit.reps,
            ),
          ) ??
          Exercise(
            id: entry.exerciseId,
            name: 'Exercise',
            unit: ExerciseUnit.reps,
          );
      final hasComment = (entry.comment?.trim().isNotEmpty ?? false);
      final metrics = formatWorkoutEntry(
        entry,
        weightUnit: provider.weightUnit,
        distanceUnit: provider.distanceUnit,
      );

      // For superset, show exercise name on left and metrics on right
      if (set.entries.length > 1) {
        entryWidgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    exercise.name,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: ScrollableMetricsText(text: metrics)),
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
                      onPressed: () =>
                          showCommentDialog(exercise.name, entry.comment!),
                      icon: const Icon(Icons.chat_bubble_outline),
                    ),
                  ),
              ],
            ),
          ),
        );
      } else {
        // For single exercise, just show metrics with comment icon aligned
        entryWidgets.add(
          SizedBox(
            height: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
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
                      onPressed: () =>
                          showCommentDialog(exercise.name, entry.comment!),
                      icon: const Icon(Icons.chat_bubble_outline),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      if (i < set.entries.length - 1) {
        entryWidgets.add(const SizedBox(height: 6));
      }
    }

    // For superset, use a different layout with set number on its own line
    if (set.entries.length > 1) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Set $setNumber',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isPRSet)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.emoji_events,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              ...entryWidgets,
            ],
          ),
        ),
      );
    }

    // For single exercise, keep the original horizontal layout
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              child: Row(
                children: [
                  Text(
                    'Set $setNumber',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isPRSet)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.emoji_events,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: entryWidgets,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
