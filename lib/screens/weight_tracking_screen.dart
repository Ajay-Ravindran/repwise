import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../models/weight_entry.dart';
import '../providers/repwise_provider.dart';
import '../utils/weight_chart_utils.dart';

const List<String> _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatFullDate(DateTime date) {
  return '${date.day} ${_monthAbbreviations[date.month - 1]} ${date.year}';
}

class WeightTrackingScreen extends StatefulWidget {
  const WeightTrackingScreen({super.key});

  @override
  State<WeightTrackingScreen> createState() => _WeightTrackingScreenState();
}

class _WeightTrackingScreenState extends State<WeightTrackingScreen> {
  Granularity _granularity = Granularity.day;
  final TextEditingController _weightController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  void _saveWeight(RepwiseProvider provider) {
    final parsed = double.tryParse(_weightController.text.trim());
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid weight')),
      );
      return;
    }
    provider.logWeight(parsed, date: _selectedDate);
    _weightController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Weight logged')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RepwiseProvider>();
    final entries = provider.weightEntries;
    final points = bucketWeightEntries(entries, _granularity);

    return Scaffold(
      appBar: AppBar(title: const Text('Weight Tracker')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Log weight',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Weight (${provider.weightUnit})',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _pickDate,
                          child: Text(_formatFullDate(_selectedDate)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _saveWeight(provider),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<Granularity>(
              segments: const [
                ButtonSegment(value: Granularity.day, label: Text('Day')),
                ButtonSegment(value: Granularity.week, label: Text('Week')),
                ButtonSegment(value: Granularity.month, label: Text('Month')),
              ],
              selected: <Granularity>{_granularity},
              onSelectionChanged: (selection) {
                setState(() => _granularity = selection.first);
              },
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: SizedBox(
                  height: 220,
                  child: points.isEmpty
                      ? const Center(
                          child: Text(
                            'No weight entries yet. Log your weight above to see progress.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _WeightLineChart(
                          points: points,
                          granularity: _granularity,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _StatsCard(entries: entries, unit: provider.weightUnit),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.entries, required this.unit});

  final List<WeightEntry> entries;
  final String unit;

  String _formatChange(double? value) {
    if (value == null) {
      return '—';
    }
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    final latest = latestWeight(entries);
    if (latest == null) {
      return const SizedBox.shrink();
    }
    final change7 = weightChangeOverDays(entries, 7);
    final change30 = weightChangeOverDays(entries, 30);
    final min = minWeight(entries);
    final max = maxWeight(entries);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _StatRow(
              label: 'Current weight',
              value: '${latest.toStringAsFixed(1)} $unit',
            ),
            _StatRow(label: 'Change (7 days)', value: _formatChange(change7)),
            _StatRow(
              label: 'Change (30 days)',
              value: _formatChange(change30),
            ),
            _StatRow(
              label: 'All-time min',
              value: min == null ? '—' : '${min.toStringAsFixed(1)} $unit',
            ),
            _StatRow(
              label: 'All-time max',
              value: max == null ? '—' : '${max.toStringAsFixed(1)} $unit',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _WeightLineChart extends StatelessWidget {
  const _WeightLineChart({required this.points, required this.granularity});

  final List<ChartPoint> points;
  final Granularity granularity;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].weight),
    ];
    final labels = [
      for (final point in points) formatBucketLabel(point.bucketStart, granularity),
    ];
    final weights = points.map((point) => point.weight).toList();
    final minY = weights.reduce((a, b) => a < b ? a : b);
    final maxY = weights.reduce((a, b) => a > b ? a : b);
    final verticalPadding = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.15;

    return LineChart(
      LineChartData(
        minY: minY - verticalPadding,
        maxY: maxY + verticalPadding,
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(labels[index], style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
