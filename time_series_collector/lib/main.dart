import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';
import 'visualization_page.dart';
import 'replay_page.dart';
import 'histogram_page.dart';


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

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final containers = ref.watch(containersProvider);
    final selectedId = ref.watch(selectedContainerIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Series Collector'),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Containers',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      )),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: containers.length,
                    itemBuilder: (context, index) {
                      final c = containers[index];
                      final selected = c.id == selectedId;
                      return ListTile(
                        title: Text(c.name),
                        selected: selected,
                        onTap: () => ref
                            .read(selectedContainerIdProvider.notifier)
                            .state = c.id,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            ref.read(containersProvider.notifier).remove(c.id);
                            if (selectedId == c.id) {
                              ref
                                  .read(selectedContainerIdProvider.notifier)
                                  .state = null;
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add container'),
                    onPressed: () async {
                      final name = await _askForText(
                        context,
                        title: 'New container',
                        hint: 'Container name',
                      );
                      if (name != null && name.trim().isNotEmpty) {
                        ref.read(containersProvider.notifier).create(name);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 3,
            child: _RightPane(selectedId: selectedId),
          ),
        ],
      ),
    );
  }

  Future<String?> _askForText(
    BuildContext context, {
    required String title,
    String? hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _RightPane extends ConsumerWidget {
  final String? selectedId;

  const _RightPane({required this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selectedId == null) {
      return const Center(child: Text('Select or create a container'));
    }

    final collectionState = ref.watch(collectionProvider);
    final sets = ref.watch(dataSetsProvider(selectedId!));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Text('Container: $selectedId'),
              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReplayPage(containerId: selectedId!),
                    ),
                  );
                },
                child: const Text('Replay'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HistogramPage(containerId: selectedId!),
                    ),
                  );
                },
                child: const Text('Histogram'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: collectionState.isRunning
                    ? null
                    : () => ref
                        .read(collectionProvider.notifier)
                        .start(selectedId!),
                child: const Text('Start collection'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: collectionState.isRunning
                    ? () async {
                        final notes = await _askForText(
                          context,
                          title: 'Notes for this data set',
                          hint: 'Optional notes',
                        );
                        ref
                            .read(collectionProvider.notifier)
                            .stop(notes: notes);
                      }
                    : null,
                child: const Text('Stop'),
              ),
            ],
          ),
        ),
        if (collectionState.isRunning)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Text(
                    'Elapsed: ${collectionState.elapsed.inSeconds} s, ignored cues: ${collectionState.ignoredCues}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: List.generate(11, (i) {
                    return ElevatedButton(
                      onPressed: () => ref
                          .read(collectionProvider.notifier)
                          .tapValue(i),
                      child: Text('$i'),
                    );
                  }),
                ),
              ],
            ),
          ),
        const Divider(),
        Expanded(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Data sets'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: sets.length,
                  itemBuilder: (context, i) {
                    final s = sets[i];
                    return ListTile(
                      title: Text(
                          'Created: ${s.createdAt.toIso8601String().substring(0, 19)}'),
                      subtitle: Text(s.notes.isEmpty ? '(no notes)' : s.notes),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VisualizationPage(
                              dataSetId: s.id,
                              containerId: s.containerId,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<String?> _askForText(
    BuildContext context, {
    required String title,
    String? hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
