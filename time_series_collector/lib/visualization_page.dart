import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'repositories.dart';

class VisualizationPage extends ConsumerWidget {
  final String dataSetId;
  final String containerId;

  const VisualizationPage({
    super.key,
    required this.dataSetId,
    required this.containerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(dataSetRepoProvider);
    final points = repo.getPoints(dataSetId);

    final spots = points
        .map((p) => FlSpot(p.tSeconds, p.value.toDouble()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data set visualization'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: spots.isEmpty
            ? const Center(child: Text('No points in this data set'))
            : LineChart(
                LineChartData(
                  minX: spots.first.x,
                  maxX: spots.last.x,
                  minY: 0,
                  maxY: 10,
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      barWidth: 2,
                      dotData: const FlDotData(show: true),
                      color: Colors.blue,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
