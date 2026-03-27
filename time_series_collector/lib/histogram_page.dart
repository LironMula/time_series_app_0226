import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'histogram.dart';
import 'models.dart';
import 'providers.dart';

class HistogramPage extends ConsumerStatefulWidget {
  final String containerId;

  const HistogramPage({super.key, required this.containerId});

  @override
  ConsumerState<HistogramPage> createState() => _HistogramPageState();
}

enum _IntervalUnit { minute, hour, day, week, month }

class _HistogramPageState extends ConsumerState<HistogramPage> {
  // Applied (chart) parameters — updated only when OK is tapped
  late DateTime _periodEnd;
  late DateTime _periodStart;
  int _intervalAmount = 1;
  _IntervalUnit _intervalUnit = _IntervalUnit.week;

  // Draft (config UI) parameters
  int _draftIntervalAmount = 1;
  _IntervalUnit _draftIntervalUnit = _IntervalUnit.week;
  late DateTime _draftPeriodStart;
  late DateTime _draftPeriodEnd;

  bool _configVisible = true;

  Duration get _interval => _durationFor(_intervalAmount, _intervalUnit);

  Duration _durationFor(int amount, _IntervalUnit unit) {
    switch (unit) {
      case _IntervalUnit.minute: return Duration(minutes: amount);
      case _IntervalUnit.hour:   return Duration(hours: amount);
      case _IntervalUnit.day:    return Duration(days: amount);
      case _IntervalUnit.week:   return Duration(days: amount * 7);
      case _IntervalUnit.month:  return Duration(days: amount * 30);
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _draftPeriodEnd = now;
    _draftPeriodStart = now.subtract(const Duration(days: 7));
    _periodEnd = _draftPeriodEnd;
    _periodStart = _draftPeriodStart;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _draftPeriodStart : _draftPeriodEnd;
    final first = isStart ? DateTime(2000) : _draftPeriodStart;
    final last  = isStart ? _draftPeriodEnd : DateTime(2100);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _draftPeriodStart = DateTime(picked.year, picked.month, picked.day);
      } else {
        _draftPeriodEnd = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  void _applyConfig() {
    setState(() {
      _intervalAmount = _draftIntervalAmount;
      _intervalUnit = _draftIntervalUnit;
      _periodStart = _draftPeriodStart;
      _periodEnd = _draftPeriodEnd;
      _configVisible = false;
    });
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final containers = ref.watch(containersProvider);
    final container = containers.firstWhere((c) => c.id == widget.containerId);
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_configVisible) ...[
              Row(
                children: [
                  const Text('Interval:'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _draftIntervalAmount,
                    items: const [
                      DropdownMenuItem(value: 1,  child: Text('1')),
                      DropdownMenuItem(value: 5,  child: Text('5')),
                      DropdownMenuItem(value: 10, child: Text('10')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _draftIntervalAmount = v);
                    },
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<_IntervalUnit>(
                    value: _draftIntervalUnit,
                    items: const [
                      DropdownMenuItem(value: _IntervalUnit.minute, child: Text('minute')),
                      DropdownMenuItem(value: _IntervalUnit.hour,   child: Text('hour')),
                      DropdownMenuItem(value: _IntervalUnit.day,    child: Text('day')),
                      DropdownMenuItem(value: _IntervalUnit.week,   child: Text('week')),
                      DropdownMenuItem(value: _IntervalUnit.month,  child: Text('month')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _draftIntervalUnit = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('From:'),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _pickDate(isStart: true),
                    child: Text(_formatDate(_draftPeriodStart)),
                  ),
                  const SizedBox(width: 16),
                  const Text('To:'),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _pickDate(isStart: false),
                    child: Text(_formatDate(_draftPeriodEnd)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _applyConfig,
                child: const Text('OK'),
              ),
            ] else
              ElevatedButton(
                onPressed: () => setState(() => _configVisible = true),
                child: const Text('Update Histogram'),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text('No data in selected period/interval'),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final chartWidth = math.max(
                          constraints.maxWidth,
                          results.length * 28.0,
                        );
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: chartWidth,
                            child: BarChart(
                              _buildBarChartData(
                                buckets: buckets,
                                results: results,
                              ),
                            ),
                          ),
                        );
                      },
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

    final titleStep = math.max(1, (results.length / 10).ceil());

    return BarChartData(
      barGroups: groups,
      alignment: BarChartAlignment.start,
      groupsSpace: 6,
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
            reservedSize: 28,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= results.length || index % titleStep != 0) {
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
