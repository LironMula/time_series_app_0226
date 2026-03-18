import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'histogram_page.dart';
import 'models.dart';
import 'providers.dart';
import 'replay_page.dart';
import 'visualization_page.dart';

void main() {
  runApp(const ProviderScope(child: TimeSeriesApp()));
}

class TimeSeriesApp extends StatelessWidget {
  const TimeSeriesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Series Collector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedContainerIdProvider);
    final tabs = [
      _ManagementTab(selectedId: selectedId),
      _CollectionTab(selectedId: selectedId),
      _VisualizationTab(selectedId: selectedId),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Time Series Collector')),
      body: tabs[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings), label: 'Management'),
          NavigationDestination(icon: Icon(Icons.sensors), label: 'Collection'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Visualisation'),
        ],
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
      ),
    );
  }
}

class _ContainerSelector extends ConsumerWidget {
  final String? selectedId;

  const _ContainerSelector({required this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final containers = ref.watch(containersProvider);
    return DropdownButton<String>(
      value: selectedId,
      hint: const Text('Select container'),
      isExpanded: true,
      items: containers
          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
          .toList(),
      onChanged: (value) =>
          ref.read(selectedContainerIdProvider.notifier).state = value,
    );
  }
}

class _ManagementTab extends ConsumerWidget {
  final String? selectedId;

  const _ManagementTab({required this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final containers = ref.watch(containersProvider);
    final selected = selectedId == null
        ? null
        : containers.where((c) => c.id == selectedId).firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ContainerSelector(selectedId: selectedId),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final name = await _askForText(context, title: 'New container');
                  if (name == null || name.trim().isEmpty) return;
                  ref.read(containersProvider.notifier).create(name.trim());
                },
                icon: const Icon(Icons.add),
                label: const Text('Create'),
              ),
              ElevatedButton.icon(
                onPressed: selected == null
                    ? null
                    : () async {
                        final name = await _askForText(
                          context,
                          title: 'Rename container',
                          initialText: selected.name,
                        );
                        if (name == null || name.trim().isEmpty) return;
                        ref.read(containersProvider.notifier).rename(selected.id, name.trim());
                      },
                icon: const Icon(Icons.edit),
                label: const Text('Rename'),
              ),
              ElevatedButton.icon(
                onPressed: selected == null
                    ? null
                    : () => ref.read(containersProvider.notifier).remove(selected.id),
                icon: const Icon(Icons.delete),
                label: const Text('Delete'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (selected != null) ...[
            Text(
              'Container properties',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: selected.settings.stopMeasurementOnTen,
                      onChanged: (value) => ref.read(containersProvider.notifier).updateSettings(
                            selected.id,
                            selected.settings.copyWith(stopMeasurementOnTen: value),
                          ),
                      title: const Text('Stop measurement if value = 10'),
                      subtitle: const Text(
                        'Applies during replay collection when the user taps value 10.',
                      ),
                    ),
                    ExpansionTile(
                      title: const Text('Histogram bucket configuration'),
                      subtitle: const Text('Configure the average-time histogram buckets.'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        ...selected.settings.buckets.map(
                          (b) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Range ${b.label}'),
                            trailing: CircleAvatar(
                              radius: 8,
                              backgroundColor: Color(b.color),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton(
                            onPressed: () async {
                              final csv = await _askForText(
                                context,
                                title: 'Buckets as min-max;color',
                                initialText: selected.settings.buckets
                                    .map(
                                      (b) => '${b.minInclusive}-${b.maxInclusive};${b.color.toRadixString(16)}',
                                    )
                                    .join(','),
                              );
                              if (csv == null || csv.isEmpty) return;
                              final parsed = _parseBucketCsv(csv);
                              if (parsed.isEmpty) return;
                              ref.read(containersProvider.notifier).updateSettings(
                                    selected.id,
                                    selected.settings.copyWith(buckets: parsed),
                                  );
                            },
                            child: const Text('Edit buckets'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () {
                    final payload = ref.read(dataSetRepoProvider).exportContainerPayload(selected);
                    Clipboard.setData(ClipboardData(text: payload));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Export copied to clipboard')),
                    );
                  },
                  child: const Text('Export container'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final payload = await _askForText(
                      context,
                      title: 'Paste exported JSON',
                    );
                    if (payload == null || payload.trim().isEmpty) return;
                    try {
                      final imported = ref.read(dataSetRepoProvider).importContainerPayload(payload);
                      final newContainer = imported.container.copyWith(
                        name: '${imported.container.name} (imported)',
                      );
                      ref.read(containersProvider.notifier).create(
                            newContainer.name,
                            settings: newContainer.settings,
                          );
                      final actual = ref.read(containersProvider).last;
                      ref
                          .read(dataSetRepoProvider)
                          .mergeImported(imported, newContainerId: actual.id);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invalid import payload')),
                        );
                      }
                    }
                  },
                  child: const Text('Import container'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<ValueBucket> _parseBucketCsv(String csv) {
    final parts = csv.split(',');
    final result = <ValueBucket>[];
    for (final part in parts) {
      final pair = part.trim().split(';');
      if (pair.length != 2) continue;
      final range = pair[0].split('-');
      if (range.length != 2) continue;
      final min = int.tryParse(range[0]);
      final max = int.tryParse(range[1]);
      final color = int.tryParse(pair[1], radix: 16);
      if (min == null || max == null || color == null) continue;
      result.add(ValueBucket(minInclusive: min, maxInclusive: max, color: color));
    }
    return result;
  }
}

class _CollectionTab extends ConsumerWidget {
  final String? selectedId;

  const _CollectionTab({required this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selectedId == null) return const Center(child: Text('Select a container in management tab'));
    final collectionState = ref.watch(collectionProvider);
    final container = ref.watch(containersProvider).firstWhere((c) => c.id == selectedId);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Container: ${container.name}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: collectionState.isRunning
                    ? null
                    : () async {
                        final config = await showDialog<CollectionStartConfig>(
                          context: context,
                          builder: (_) => _CollectionConfigDialog(settings: container.settings),
                        );
                        if (config == null) return;
                        ref.read(collectionProvider.notifier).applyStartConfig(selectedId!, config);
                        ref.read(collectionProvider.notifier).start(selectedId!);
                      },
                child: const Text('Start collection'),
              ),
              ElevatedButton(
                onPressed: collectionState.isRunning
                    ? () async {
                        final notes = await _askForText(context, title: 'Notes');
                        ref.read(collectionProvider.notifier).stop(notes: notes);
                      }
                    : null,
                child: const Text('Stop collection'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReplayPage(containerId: selectedId!)),
                ),
                child: const Text('Replay mode'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (collectionState.isRunning) ...[
            Text('Elapsed: ${collectionState.elapsed.inSeconds}s | ignored cues: ${collectionState.ignoredCues}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: List.generate(
                11,
                (i) => ElevatedButton(
                  onPressed: () => ref.read(collectionProvider.notifier).tapValue(i),
                  child: Text('$i'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VisualizationTab extends ConsumerStatefulWidget {
  final String? selectedId;

  const _VisualizationTab({required this.selectedId});

  @override
  ConsumerState<_VisualizationTab> createState() => _VisualizationTabState();
}

class _VisualizationTabState extends ConsumerState<_VisualizationTab> {
  final Set<String> _selectedSetIds = <String>{};

  @override
  void didUpdateWidget(covariant _VisualizationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      _selectedSetIds.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedId;
    if (selectedId == null) {
      return const Center(child: Text('Select a container in management tab'));
    }

    final sets = ref.watch(dataSetsProvider(selectedId));
    final validIds = sets.map((s) => s.id).toSet();
    _selectedSetIds.removeWhere((id) => !validIds.contains(id));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: _selectedSetIds.isEmpty
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VisualizationPage(
                              containerId: selectedId,
                              selectedDataSetIds: _selectedSetIds.toList(),
                            ),
                          ),
                        ),
                child: const Text('Compare selected sets'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => HistogramPage(containerId: selectedId)),
                ),
                child: const Text('Period histogram'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: sets.length,
              itemBuilder: (context, index) {
                final set = sets[index];
                final selected = _selectedSetIds.contains(set.id);
                return CheckboxListTile(
                  value: selected,
                  title: Text(set.createdAt.toIso8601String().substring(0, 19)),
                  subtitle: Text(set.notes.isEmpty ? '(no notes)' : set.notes),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedSetIds.add(set.id);
                      } else {
                        _selectedSetIds.remove(set.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionConfigDialog extends StatefulWidget {
  final ContainerSettings settings;

  const _CollectionConfigDialog({required this.settings});

  @override
  State<_CollectionConfigDialog> createState() => _CollectionConfigDialogState();
}

class _CollectionConfigDialogState extends State<_CollectionConfigDialog> {
  late bool _assisted;
  late int _dt;
  late CueType _cue;

  @override
  void initState() {
    super.initState();
    _assisted = widget.settings.assistedEnabled;
    _dt = widget.settings.assistedDt.inSeconds;
    _cue = widget.settings.cueType;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Collection configuration'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            value: _assisted,
            onChanged: (v) => setState(() => _assisted = v),
            title: const Text('Assisted collection'),
          ),
          Row(
            children: [
              const Text('Reminder every (seconds):'),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _dt.toDouble(),
                  min: 2,
                  max: 60,
                  divisions: 58,
                  label: '$_dt',
                  onChanged: _assisted ? (v) => setState(() => _dt = v.round()) : null,
                ),
              ),
            ],
          ),
          DropdownButton<CueType>(
            value: _cue,
            items: CueType.values
                .map((cue) => DropdownMenuItem(value: cue, child: Text(cue.name)))
                .toList(),
            onChanged: _assisted ? (v) => setState(() => _cue = v ?? CueType.beep) : null,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            CollectionStartConfig(
              assistedEnabled: _assisted,
              assistedDtSeconds: _dt,
              cueType: _cue,
            ),
          ),
          child: const Text('Start'),
        ),
      ],
    );
  }
}

Future<String?> _askForText(
  BuildContext context, {
  required String title,
  String? initialText,
}) {
  final controller = TextEditingController(text: initialText);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, maxLines: null),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('OK')),
        ],
      );
    },
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
