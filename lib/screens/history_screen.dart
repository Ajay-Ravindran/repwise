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
      for (final set in session.sets) {
        final MuscleGroup? group = provider.muscleGroupById(set.muscleGroupId);
        if (group != null) {
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
                    .map((name) => Chip(label: Text(name)))
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
    final groupsById = <String, MuscleGroup?>{};
    for (final set in session.sets) {
      groupsById[set.muscleGroupId] = provider.muscleGroupById(
        set.muscleGroupId,
      );
    }
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
                  '${session.sets.length} set${session.sets.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Workout options',
                  onPressed: session.sets.isEmpty
                      ? null
                      : () => _showSetOptions(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: groupsById.values
                  .whereType<MuscleGroup>()
                  .map(
                    (group) => Chip(
                      avatar: CircleAvatar(
                        backgroundColor: paletteResolver(group.name),
                      ),
                      label: Text(group.name),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                for (final set in session.sets)
                  _WorkoutSetTile(set: set, provider: provider),
              ],
            ),
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

  void _showSetOptions(BuildContext context) {
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
                ...session.sets.asMap().entries.map((entry) {
                  final index = entry.key;
                  final set = entry.value;
                  final summary = _setSummary(set);
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
                      _confirmDeleteSet(context, set);
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

  Future<void> _confirmDeleteSet(BuildContext context, WorkoutSet set) async {
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
      setId: set.id,
    );
    if (!removed && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to delete set.')));
    }
  }
}

class _WorkoutSetTile extends StatelessWidget {
  const _WorkoutSetTile({required this.set, required this.provider});

  final WorkoutSet set;
  final GymLogProvider provider;

  @override
  Widget build(BuildContext context) {
    final MuscleGroup? group = provider.muscleGroupById(set.muscleGroupId);
    final theme = Theme.of(context);
    final baseSurface = theme.colorScheme.surfaceContainerHighest;
    final double tintAlpha = theme.brightness == Brightness.dark ? 0.35 : 0.6;
    final Color surfaceTint = baseSurface.withValues(alpha: tintAlpha);

    final List<Widget> entryWidgets = <Widget>[];
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

      entryWidgets.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: Text(exercise.name)),
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
            const SizedBox(width: 12),
            Flexible(
              child: ScrollableMetricsText(
                text: formatWorkoutEntry(entry),
                backgroundColor: surfaceTint,
              ),
            ),
          ],
        ),
      );

      if (i < set.entries.length - 1) {
        entryWidgets.add(const SizedBox(height: 6));
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surfaceTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (set.isSuperset)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: const Chip(label: Text('Superset')),
                ),
              ),
            ...entryWidgets,
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
