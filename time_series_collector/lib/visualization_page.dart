import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class VisualizationPage extends ConsumerStatefulWidget {
  final String containerId;
  final List<String> selectedDataSetIds;

  const VisualizationPage({
    super.key,
    required this.containerId,
    required this.selectedDataSetIds,
  });

  @override
  ConsumerState<VisualizationPage> createState() => _VisualizationPageState();
}

class _VisualizationPageState extends ConsumerState<VisualizationPage> {
  String? _highlightedSeriesId;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(dataSetRepoProvider);
    final dataSets = ref.watch(dataSetsProvider(widget.containerId));
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
    for (var i = 0; i < widget.selectedDataSetIds.length; i++) {
      final id = widget.selectedDataSetIds[i];
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

    final visibleHighlightedId = series.any((item) => item.id == _highlightedSeriesId)
        ? _highlightedSeriesId
        : null;

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
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              _highlightedSeriesId = visibleHighlightedId == item.id ? null : item.id;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: visibleHighlightedId == item.id
                                  ? item.color.withOpacity(0.12)
                                  : null,
                              border: Border.all(
                                color: visibleHighlightedId == item.id
                                    ? item.color
                                    : Theme.of(context).colorScheme.outlineVariant,
                                width: visibleHighlightedId == item.id ? 2 : 1,
                              ),
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
                                    style: TextStyle(
                                      fontWeight: visibleHighlightedId == item.id
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                              barWidth: visibleHighlightedId == item.id ? 4 : 2,
                              dotData: FlDotData(show: visibleHighlightedId == item.id),
                              color: visibleHighlightedId == null || visibleHighlightedId == item.id
                                  ? item.color
                                  : item.color.withOpacity(0.25),
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
