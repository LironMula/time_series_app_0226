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
    final dataSets = ref.watch(dataSetsProvider(containerId));
    final dataSetMap = {for (final set in dataSets) set.id: set};

    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];

    final series = <({String id, String label, Color color, List<FlSpot> spots})>[];
    for (var i = 0; i < selectedDataSetIds.length; i++) {
      final id = selectedDataSetIds[i];
      final points = repo.getPoints(id);
      if (points.isEmpty) continue;
      final set = dataSetMap[id];
      final label = set == null
          ? id
          : '${set.createdAt.toIso8601String().substring(0, 19)}${set.notes.isEmpty ? '' : ' — ${set.notes}'}';
      series.add((
        id: id,
        label: label,
        color: colors[i % colors.length],
        spots: points.map((p) => FlSpot(p.tSeconds, p.value.toDouble())).toList(),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Data sets visualization')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: series.isEmpty
            ? const Center(child: Text('No points in selected data sets'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final item in series)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: item.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 260),
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 10,
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                        ),
                        lineBarsData: [
                          for (final item in series)
                            LineChartBarData(
                              spots: item.spots,
                              isCurved: false,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              color: item.color,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
