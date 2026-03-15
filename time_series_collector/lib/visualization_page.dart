import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class VisualizationPage extends ConsumerWidget {
  final String containerId;
  final List<String> selectedDataSetIds;

  const VisualizationPage({
    super.key,
    required this.containerId,
    required this.selectedDataSetIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(dataSetRepoProvider);

    final lines = selectedDataSetIds.map((id) {
      final points = repo.getPoints(id);
      return points.map((p) => FlSpot(p.tSeconds, p.value.toDouble())).toList();
    }).where((s) => s.isNotEmpty).toList();

    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Data sets visualization')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: lines.isEmpty
            ? const Center(child: Text('No points in selected data sets'))
            : LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 10,
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  ),
                  lineBarsData: [
                    for (int i = 0; i < lines.length; i++)
                      LineChartBarData(
                        spots: lines[i],
                        isCurved: false,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                        color: colors[i % colors.length],
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
