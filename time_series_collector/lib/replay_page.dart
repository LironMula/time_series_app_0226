import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';
import 'replay.dart';

class ReplayPage extends ConsumerStatefulWidget {
  final String containerId;

  const ReplayPage({super.key, required this.containerId});

  @override
  ConsumerState<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends ConsumerState<ReplayPage> {
  String? _selectedSourceId;
  bool _starredOnly = false;

  @override
  Widget build(BuildContext context) {
    final allDataSets = ref.watch(dataSetsProvider(widget.containerId));
    final replayState = ref.watch(replayProvider);
    final replayCtrl = ref.read(replayProvider.notifier);
    final collectionState = ref.watch(collectionProvider);
    final collectionCtrl = ref.read(collectionProvider.notifier);
    final container = ref.watch(containersProvider).firstWhere((c) => c.id == widget.containerId);
    final settings = container.settings;

    final visibleDataSets = _starredOnly ? allDataSets.where((s) => s.starred).toList() : allDataSets;
    final selectedSource = allDataSets.where((s) => s.id == _selectedSourceId).firstOrNull;

    double factorFromSettings(DataSet ds) {
      if (settings.replayStretchMode == ReplayStretchMode.factor) {
        return settings.replayStretchFactor;
      }
      final points = ref.read(dataSetRepoProvider).getPoints(ds.id);
      if (points.isEmpty || settings.replayFixedDurationSeconds <= 0) return 1;
      final sourceDuration = points.last.tSeconds;
      if (sourceDuration <= 0) return 1;
      return settings.replayFixedDurationSeconds / sourceDuration;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Replay')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Choose data set to replay:'),
                const Spacer(),
                FilterChip(
                  label: const Text('Starred only'),
                  selected: _starredOnly,
                  onSelected: (value) => setState(() => _starredOnly = value),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              isExpanded: true,
              value: visibleDataSets.any((s) => s.id == _selectedSourceId) ? _selectedSourceId : null,
              hint: const Text('Select data set'),
              items: visibleDataSets
                  .map((s) => DropdownMenuItem<String>(
                        value: s.id,
                        child: Text('${s.starred ? '★ ' : ''}${s.createdAt.toIso8601String().substring(0, 19)} - ${s.notes}'),
                      ))
                  .toList(),
              onChanged: (id) {
                setState(() {
                  _selectedSourceId = id;
                });
              },
            ),
            if (selectedSource != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    collectionCtrl.toggleSetStarred(selectedSource.id);
                  },
                  icon: Icon(selectedSource.starred ? Icons.star : Icons.star_border),
                  label: Text(selectedSource.starred ? 'Unstar set' : 'Star set'),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: selectedSource == null || collectionState.isRunning
                      ? null
                      : () {
                          final targetSet = collectionCtrl.createReplayCollection(widget.containerId, selectedSource.id);
                          if (targetSet == null) return;
                          collectionCtrl.startWithExistingSet(targetSet);
                          replayCtrl.startReplay(
                            selectedSource,
                            stretchFactor: factorFromSettings(selectedSource),
                            interpolationEnabled: settings.replayInterpolationEnabled,
                          );
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start replay collection'),
                ),
                ElevatedButton.icon(
                  onPressed: collectionState.isRunning
                      ? () {
                          collectionCtrl.stop();
                          replayCtrl.stop();
                        }
                      : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Finish measurement'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: settings.replayInterpolationEnabled,
              onChanged: (value) => ref.read(containersProvider.notifier).updateSettings(
                    widget.containerId,
                    settings.copyWith(replayInterpolationEnabled: value),
                  ),
              title: const Text('Replay interpolation'),
            ),
            Row(
              children: [
                const Text('Stretch mode: '),
                DropdownButton<ReplayStretchMode>(
                  value: settings.replayStretchMode,
                  items: ReplayStretchMode.values
                      .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(containersProvider.notifier).updateSettings(
                          widget.containerId,
                          settings.copyWith(replayStretchMode: value),
                        );
                  },
                ),
              ],
            ),
            if (settings.replayStretchMode == ReplayStretchMode.factor)
              Slider(
                value: settings.replayStretchFactor,
                min: 0.5,
                max: 2,
                divisions: 15,
                label: settings.replayStretchFactor.toStringAsFixed(2),
                onChanged: (v) => ref.read(containersProvider.notifier).updateSettings(
                      widget.containerId,
                      settings.copyWith(replayStretchFactor: v),
                    ),
              )
            else
              Row(
                children: [
                  const Text('Fixed duration (s):'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      initialValue: '${settings.replayFixedDurationSeconds}',
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed == null || parsed <= 0) return;
                        ref.read(containersProvider.notifier).updateSettings(
                              widget.containerId,
                              settings.copyWith(replayFixedDurationSeconds: parsed),
                            );
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (replayState.isRunning && replayState.nextTarget != null) ...[
              Text('Next target value: ${replayState.nextTarget!.value}'),
              Builder(builder: (context) {
                final stretchedTime =
                    (replayState.elapsed.inMilliseconds / 1000.0) / replayState.stretchFactor;
                final dt = replayState.nextTarget!.tSeconds - stretchedTime;
                return Text('Countdown: ${dt.toStringAsFixed(2)} seconds');
              }),
            ],
            const Divider(),
            Text(
              collectionState.isRunning
                  ? 'You can collect values while replay is running:'
                  : 'Choose a source and press "Start replay collection".',
            ),
            Wrap(
              spacing: 4,
              children: List.generate(
                11,
                (i) => ElevatedButton(
                  onPressed: collectionState.isRunning
                      ? () => ref.read(collectionProvider.notifier).tapValue(i)
                      : null,
                  child: Text('$i'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
