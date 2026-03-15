import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'replay.dart';
import 'repositories.dart';

class ReplayPage extends ConsumerWidget {
  final String containerId;

  const ReplayPage({super.key, required this.containerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataSets = ref.watch(dataSetsProvider(containerId));
    final replayState = ref.watch(replayProvider);
    final replayCtrl = ref.read(replayProvider.notifier);
    final dataRepo = ref.read(dataSetRepoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Replay'),
      ),
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
              items: dataSets.map((s) {
                return DropdownMenuItem<String>(
                  value: s.id,
                  child: Text(
                    '${s.createdAt.toIso8601String().substring(0, 19)}'
                    '${s.notes.isEmpty ? '' : ' - ${s.notes}'}',
                  ),
                );
              }).toList(),
              onChanged: (id) {
                if (id == null) return;
                final ds = dataSets.firstWhere((s) => s.id == id);
                replayCtrl.startReplay(ds,
                    stretchFactor: replayState.stretchFactor);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Time stretch'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: replayState.stretchFactor,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label:
                        replayState.stretchFactor.toStringAsFixed(2),
                    onChanged: (v) {
                      if (replayState.sourceSet == null) return;
                      replayCtrl.startReplay(
                        replayState.sourceSet!,
                        stretchFactor: v,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (replayState.isRunning &&
                replayState.nextTarget != null) ...[
              Text(
                  'Elapsed (replay clock): ${replayState.elapsed.inMilliseconds / 1000.0}s'),
              const SizedBox(height: 8),
              Text(
                  'Next target value: ${replayState.nextTarget!.value}'),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final scaled =
                      replayState.elapsed.inMilliseconds / 1000.0;
                  final stretchedTime =
                      scaled / replayState.stretchFactor;
                  final dt = replayState.nextTarget!.tSeconds -
                      stretchedTime;
                  return Text(
                      'Countdown: ${dt.toStringAsFixed(2)} seconds');
                },
              ),
            ] else
              const Text('Replay not running'),
          ],
        ),
      ),
    );
  }
}
