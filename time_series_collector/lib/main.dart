import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'database.dart';
import 'file_saver.dart';
import 'histogram_page.dart';
import 'models.dart';
import 'providers.dart';
import 'replay.dart';
import 'replay_page.dart';
import 'visualization_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWebNoWebWorker;
  } else if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Android/iOS: sqflite uses native platform channels, no setup needed
  runApp(const ProviderScope(child: TimeSeriesAppLoader()));
}

class TimeSeriesAppLoader extends ConsumerStatefulWidget {
  const TimeSeriesAppLoader({Key? key}) : super(key: key);

  @override
  ConsumerState<TimeSeriesAppLoader> createState() => _TimeSeriesAppLoaderState();
}

class _TimeSeriesAppLoaderState extends ConsumerState<TimeSeriesAppLoader> {
  bool _shouldRetryInit = false;

  @override
  Widget build(BuildContext context) {
    // Create a new instance if retrying
    final initFuture = _shouldRetryInit
        ? ref.refresh(initializeRepositoriesProvider)
        : ref.watch(initializeRepositoriesProvider);

    return initFuture.when(
      data: (_) => const TimeSeriesApp(),
      loading: () => const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (err, stack) {
        if (err is DatabaseVersionMismatchException) {
          return MaterialApp(
            home: Scaffold(
              body: _buildVersionMismatchDialog(err),
            ),
          );
        }
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Initialization error: $err'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVersionMismatchDialog(DatabaseVersionMismatchException error) {
    final needsDowngrade = error.storedVersion > error.currentVersion;

    return Center(
      child: AlertDialog(
        title: const Text('Database Version Mismatch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              needsDowngrade
                  ? 'Your data is from a newer version of the app (v${error.storedVersion}). '
                      'The current app is version v${error.currentVersion}.'
                  : 'The database format has changed between app versions. '
                      'Your data (v${error.storedVersion}) is incompatible with the current app (v${error.currentVersion}).',
            ),
            const SizedBox(height: 16),
            if (needsDowngrade)
              const Text(
                'To use your data, please downgrade the application to a newer version that supports this data format.',
                style: TextStyle(color: Colors.orange),
              )
            else
              const Text(
                'Choose an option below to proceed:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
          ],
        ),
        actions: [
          if (needsDowngrade)
            TextButton(
              onPressed: () => _showDowngradeInfo(context, error),
              child: const Text('How to Downgrade'),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          if (!needsDowngrade)
            ElevatedButton(
              onPressed: () => _eraseData(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text(
                'Erase Existing Data',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  void _showDowngradeInfo(BuildContext context, DatabaseVersionMismatchException error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Downgrade Instructions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your data was created with app version v${error.storedVersion}, '
              'but you have version v${error.currentVersion} installed.\n\n'
              'To access your data, you need to downgrade to version v${error.storedVersion} or later '
              '(but before v${error.currentVersion}).\n\n'
              'Options:\n'
              '• Check the app store for previous versions\n'
              '• Download an older APK/IPA build\n'
              '• Restore from a backup of the older app version',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _eraseData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Data Erasure'),
        content: const Text(
          'All containers, datasets, and measurements will be permanently deleted. '
          'This action cannot be undone. A new "default" container will be created.\n\n'
          'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Yes, Erase All Data',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseHelper.instance.eraseAllData();
        setState(() {
          _shouldRetryInit = true;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error erasing data: $e')),
          );
        }
      }
    }
  }
}

void _showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> _showPendingStopDialog(
  BuildContext context,
  WidgetRef ref,
  CollectionState state,
) async {
  if (!state.isAwaitingNotes || state.activeSet == null) return;

  final title = switch (state.finishReason) {
    MeasurementFinishReason.stopAtTen => 'Measurement finished at value 10',
    MeasurementFinishReason.ignoredReminders => 'Measurement ended after ignored reminders',
    _ => 'Finish measurement',
  };

  final subtitle = switch (state.finishReason) {
    MeasurementFinishReason.stopAtTen => 'Value 10 was recorded and the measurement has ended.',
    MeasurementFinishReason.ignoredReminders =>
      'Three consecutive reminders were ignored. You can still add notes now.',
    _ => 'Add optional notes for the finished measurement.',
  };

  final notes = await _askForText(
    context,
    title: title,
    helperText: subtitle,
  );
  ref.read(collectionProvider.notifier).finalizeStop(notes: notes);
}

class TimeSeriesApp extends ConsumerWidget {
  const TimeSeriesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Time Series Collector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      themeMode: themeMode,
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
          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis)))
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

    Future<void> exportContainerToFile(DataContainer container) async {
      final fileName = '${container.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')}.json';
      String? savePath;
      if (!kIsWeb) {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'JSON', extensions: ['json']),
          ],
        );
        if (location == null) return;
        savePath = location.path;
      }
      final payload = ref.read(dataSetRepoProvider).exportContainerPayload(container);
      await saveTextFile(
        suggestedName: fileName,
        path: savePath,
        contents: payload,
      );
      if (context.mounted) {
        _showMessage(
          context,
          kIsWeb ? 'Container export downloaded' : 'Container exported to $savePath',
        );
      }
    }

    Future<void> importContainerFromFile() async {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;
      try {
        final payload = await file.readAsString();
        final imported = ref.read(dataSetRepoProvider).importContainerPayload(payload);
        final newContainer = imported.container.copyWith(
          name: '${imported.container.name} (imported)',
        );
        ref.read(containersProvider.notifier).create(
              newContainer.name,
              settings: newContainer.settings,
            );
        final actual = ref.read(containersProvider).last;
        ref.read(dataSetRepoProvider).mergeImported(imported, newContainerId: actual.id);
        ref.read(dataSetRefreshProvider.notifier).state++;
        ref.read(selectedContainerIdProvider.notifier).state = actual.id;
        if (context.mounted) {
          _showMessage(context, 'Imported container from ${file.name}');
        }
      } catch (_) {
        if (context.mounted) {
          _showMessage(context, 'Invalid import file');
        }
      }
    }

    Future<void> exportAllContainersToFile() async {
      const fileName = 'containers_export.json';
      String? savePath;
      if (!kIsWeb) {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])],
        );
        if (location == null) return;
        savePath = location.path;
      }
      final payload = const JsonEncoder.withIndent('  ').convert({
        'containers': containers.map((c) => jsonDecode(ref.read(dataSetRepoProvider).exportContainerPayload(c))).toList(),
      });
      await saveTextFile(
        suggestedName: fileName,
        path: savePath,
        contents: payload,
      );
      if (context.mounted) {
        _showMessage(
          context,
          kIsWeb ? 'Containers export downloaded' : 'All containers exported to $savePath',
        );
      }
    }

    Future<void> importAllContainersFromFile() async {
      final file = await openFile(
        acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])],
      );
      if (file == null) return;
      try {
        final payload = await file.readAsString();
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        final entries = (decoded['containers'] as List?) ?? const [];
        for (final entry in entries) {
          final imported = ref
              .read(dataSetRepoProvider)
              .importContainerPayload(jsonEncode(entry));
          final newContainer = imported.container.copyWith(
            name: '${imported.container.name} (imported)',
          );
          ref.read(containersProvider.notifier).create(
                newContainer.name,
                settings: newContainer.settings,
              );
          final actual = ref.read(containersProvider).last;
          ref.read(dataSetRepoProvider).mergeImported(imported, newContainerId: actual.id);
          ref.read(selectedContainerIdProvider.notifier).state = actual.id;
        }
        ref.read(dataSetRefreshProvider.notifier).state++;
        if (context.mounted) {
          _showMessage(context, 'Imported ${entries.length} container(s) from file');
        }
      } catch (_) {
        if (context.mounted) {
          _showMessage(context, 'Invalid containers import file');
        }
      }
    }

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
                  final name = await _askForText(
                    context,
                    title: 'New container',
                    singleLine: true,
                    submitLabel: 'Create',
                  );
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
                          singleLine: true,
                          submitLabel: 'Rename',
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
              ElevatedButton.icon(
                onPressed: exportAllContainersToFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Export all'),
              ),
              ElevatedButton.icon(
                onPressed: importAllContainersFromFile,
                icon: const Icon(Icons.download),
                label: const Text('Import all'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 24),
          const Divider(thickness: 2),
          const SizedBox(height: 8),
          Text(
            'Global settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Background mode:'),
                      const SizedBox(width: 16),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode),
                          ),
                        ],
                        selected: {ref.watch(themeModeProvider)},
                        onSelectionChanged: (s) =>
                            ref.read(themeModeProvider.notifier).state = s.first,
                      ),
                    ],
                  ),
                  if (ref.watch(themeModeProvider) == ThemeMode.dark) ...[
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Low light'),
                      subtitle: const Text(
                          'Dims value buttons to reduce emitted light'),
                      value: ref.watch(lowLightProvider),
                      onChanged: (v) =>
                          ref.read(lowLightProvider.notifier).state = v,
                    ),
                  ],
                ],
              ),
            ),
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
                        'Applies to all measurement modes. Value 10 is saved first, then the measurement ends.',
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
                    _showMessage(context, 'Export copied to clipboard');
                  },
                  child: const Text('Copy export JSON'),
                ),
                ElevatedButton(
                  onPressed: () => exportContainerToFile(selected),
                  child: const Text('Export container to file'),
                ),
                ElevatedButton(
                  onPressed: importContainerFromFile,
                  child: const Text('Import container from file'),
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
                      ref.read(dataSetRepoProvider).mergeImported(imported, newContainerId: actual.id);
                      ref.read(dataSetRefreshProvider.notifier).state++;
                      ref.read(selectedContainerIdProvider.notifier).state = actual.id;
                    } catch (_) {
                      if (context.mounted) {
                        _showMessage(context, 'Invalid import payload');
                      }
                    }
                  },
                  child: const Text('Import from pasted JSON'),
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

class _CollectionTab extends ConsumerStatefulWidget {
  final String? selectedId;

  const _CollectionTab({required this.selectedId});

  @override
  ConsumerState<_CollectionTab> createState() => _CollectionTabState();
}

class _CollectionTabState extends ConsumerState<_CollectionTab> {
  bool _showingPendingStopDialog = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<CollectionState>(collectionProvider, (previous, next) async {
      if (!mounted || _showingPendingStopDialog || !next.isAwaitingNotes) return;
      if (!ref.read(collectionProvider.notifier).claimPendingStopDialog()) return;
      _showingPendingStopDialog = true;
      await _showPendingStopDialog(context, ref, next);
      ref.read(replayProvider.notifier).stop();
      _showingPendingStopDialog = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedId;
    if (selectedId == null) return const Center(child: Text('Select a container in management tab'));
    final collectionState = ref.watch(collectionProvider);
    final container = ref.watch(containersProvider).firstWhere((c) => c.id == selectedId);
    final isDarkLowLight = ref.watch(themeModeProvider) == ThemeMode.dark &&
        ref.watch(lowLightProvider);
    final buttonOpacity = !isDarkLowLight
        ? 1.0
        : (collectionState.ignoredCues >= 1 ? 0.5 : 0.3);

    Future<void> stopCollectionManually() async {
      ref.read(collectionProvider.notifier).requestStop(MeasurementFinishReason.manual);
    }

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
                onPressed: collectionState.isRunning || collectionState.isAwaitingNotes
                    ? null
                    : () async {
                        final config = await showDialog<CollectionStartConfig>(
                          context: context,
                          builder: (_) => _CollectionConfigDialog(settings: container.settings),
                        );
                        if (config == null) return;
                        ref.read(collectionProvider.notifier).applyStartConfig(selectedId, config);
                        ref.read(collectionProvider.notifier).start(selectedId);
                      },
                child: const Text('Start collection'),
              ),
              ElevatedButton(
                onPressed: collectionState.isRunning ? stopCollectionManually : null,
                child: const Text('Stop collection'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReplayPage(containerId: selectedId)),
                ),
                child: const Text('Replay mode'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (collectionState.isRunning || collectionState.isAwaitingNotes) ...[
            Text(
              'Elapsed: ${collectionState.elapsed.inSeconds}s | ignored cues: ${collectionState.ignoredCues}',
            ),
            const SizedBox(height: 4),
            Text('Current value: ${collectionState.currentValue?.toString() ?? '—'}'),
            if (container.settings.stopMeasurementOnTen)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Tapping value 10 records the point and ends the measurement.'),
              ),
            const SizedBox(height: 8),
            Opacity(
              opacity: buttonOpacity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  11,
                  (i) {
                    final bucket = container.settings.buckets
                        .where((b) => b.contains(i))
                        .firstOrNull;
                    final bgColor = bucket != null ? Color(bucket.color) : null;
                    final fgColor = bgColor != null
                        ? (bgColor.computeLuminance() > 0.4
                            ? Colors.black87
                            : Colors.white)
                        : null;
                    return SizedBox(
                      width: 72,
                      height: 72,
                      child: ElevatedButton(
                        onPressed: collectionState.isRunning
                            ? () => ref
                                .read(collectionProvider.notifier)
                                .tapValue(i)
                            : null,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: bgColor,
                          foregroundColor: fgColor,
                          disabledBackgroundColor:
                              bgColor?.withValues(alpha: 0.4),
                        ),
                        child: Text(
                          '$i',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reminder every (seconds):'),
              Slider(
                value: _dt.toDouble(),
                min: 2,
                max: 60,
                divisions: 58,
                label: '$_dt',
                onChanged: _assisted ? (v) => setState(() => _dt = v.round()) : null,
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
  bool singleLine = false,
  String? helperText,
  String submitLabel = 'OK',
}) {
  final controller = TextEditingController(text: initialText);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: singleLine ? 1 : null,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(context, controller.text),
          decoration: InputDecoration(helperText: helperText),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(submitLabel)),
        ],
      );
    },
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    for (final item in this) {
      return item;
    }
    return null;
  }
}
