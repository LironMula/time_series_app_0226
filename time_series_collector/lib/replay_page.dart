import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';
import 'replay.dart';

class ReplayPage extends ConsumerWidget {
  final String containerId;

  const ReplayPage({super.key, required this.containerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataSets = ref.watch(dataSetsProvider(containerId));
    final replayState = ref.watch(replayProvider);
    final replayCtrl = ref.read(replayProvider.notifier);
    final collectionState = ref.watch(collectionProvider);
    final container = ref.watch(containersProvider).firstWhere((c) => c.id == containerId);
    final settings = container.settings;

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
            const Text('Choose data set to replay:'),
            const SizedBox(height: 8),
            DropdownButton<String>(
              isExpanded: true,
              value: replayState.sourceSet?.id,
              hint: const Text('Select data set'),
              items: dataSets
                  .map((s) => DropdownMenuItem<String>(
                        value: s.id,
                        child: Text('${s.createdAt.toIso8601String().substring(0, 19)} - ${s.notes}'),
                      ))
                  .toList(),
              onChanged: (id) {
                if (id == null) return;
                final ds = dataSets.firstWhere((s) => s.id == id);
                replayCtrl.startReplay(
                  ds,
                  stretchFactor: factorFromSettings(ds),
                  interpolationEnabled: settings.replayInterpolationEnabled,
                );
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: settings.replayInterpolationEnabled,
              onChanged: (value) => ref.read(containersProvider.notifier).updateSettings(
                    containerId,
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
                          containerId,
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
                      containerId,
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
                              containerId,
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
                  : 'Start a collection session to collect while replaying.',
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
