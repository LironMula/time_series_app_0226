import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'histogram.dart';
import 'models.dart';
import 'providers.dart';
import 'repositories.dart';

class HistogramPage extends ConsumerStatefulWidget {
  final String containerId;

  const HistogramPage({super.key, required this.containerId});

  @override
  ConsumerState<HistogramPage> createState() => _HistogramPageState();
}

class _HistogramPageState extends ConsumerState<HistogramPage> {
  late DateTime _periodEnd;
  late DateTime _periodStart;
  Duration _interval = const Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    _periodEnd = DateTime.now();
    _periodStart = _periodEnd.subtract(const Duration(hours: 6));
  }

  @override
  Widget build(BuildContext context) {
    final containers = ref.watch(containersProvider);
    final container = containers
        .firstWhere((c) => c.id == widget.containerId);
    final buckets = container.settings.buckets;

    final repo = ref.read(dataSetRepoProvider);
    final agg = HistogramAggregator(repo);
    final results = agg.aggregate(
      containerId: widget.containerId,
      buckets: buckets,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      interval: _interval,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histogram'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Interval:'),
                const SizedBox(width: 8),
                DropdownButton<Duration>(
                  value: _interval,
                  items: const [
                    DropdownMenuItem(
                      value: Duration(minutes: 1),
                      child: Text('1 min'),
                    ),
                    DropdownMenuItem(
                      value: Duration(minutes: 15),
                      child: Text('15 min'),
                    ),
                    DropdownMenuItem(
                      value: Duration(minutes: 30),
                      child: Text('30 min'),
                    ),
                    DropdownMenuItem(
                      value: Duration(hours: 1),
                      child: Text('1 hour'),
                    ),
                    DropdownMenuItem(
                      value: Duration(hours: 2),
                      child: Text('2 hours'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _interval = v;
                    });
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _periodEnd = DateTime.now();
                      _periodStart =
                          _periodEnd.subtract(const Duration(hours: 6));
                    });
                  },
                  child: const Text('Last 6 hours'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _periodEnd = DateTime.now();
                      _periodStart =
                          _periodEnd.subtract(const Duration(days: 1));
                    });
                  },
                  child: const Text('Last day'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child:
                          Text('No data in selected period/interval'),
                    )
                  : BarChart(
                      _buildBarChartData(
                        buckets: buckets,
                        results: results,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  BarChartData _buildBarChartData({
    required List<ValueBucket> buckets,
    required List<IntervalBucketResult> results,
  }) {
    final groups = <BarChartGroupData>[];

    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      final stacks = <BarChartRodStackItem>[];
      double from = 0;
      for (final b in buckets) {
        final sec = r.secondsPerBucket[b] ?? 0;
        final to = from + sec;
        stacks.add(
          BarChartRodStackItem(
            from,
            to,
            Color(b.color),
          ),
        );
        from = to;
      }

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: stacks.isEmpty ? 0 : stacks.last.toY,
              rodStackItems: stacks,
              width: 14,
            ),
          ],
        ),
      );
    }

    return BarChartData(
      barGroups: groups,
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= results.length) {
                return const SizedBox.shrink();
              }
              final t = results[index].intervalStart;
              final label =
                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              return SideTitleWidget(
                axisSide: meta.axisSide,
                space: 4,
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      ),
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: true),
    );
  }
}
