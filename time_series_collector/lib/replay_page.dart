import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'measurement_value_entry.dart';
import 'models.dart';
import 'providers.dart';
import 'replay.dart';


Future<void> _showReplayPendingStopDialog(
  BuildContext context,
  WidgetRef ref,
  CollectionState state,
) async {
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

  final controller = TextEditingController();
  final notes = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: null,
        decoration: InputDecoration(helperText: subtitle),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => Navigator.pop(context, controller.text),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    ),
  );
  ref.read(collectionProvider.notifier).finalizeStop(notes: notes);
}

class ReplayPage extends ConsumerStatefulWidget {
  final String containerId;

  const ReplayPage({super.key, required this.containerId});

  @override
  ConsumerState<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends ConsumerState<ReplayPage> {
  String? _selectedSourceId;
  bool _starredOnly = false;
  bool _showingPendingStopDialog = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<CollectionState>(collectionProvider, (previous, next) async {
      if (!mounted || _showingPendingStopDialog || !next.isAwaitingNotes) return;
      if (!ref.read(collectionProvider.notifier).claimPendingStopDialog()) return;
      _showingPendingStopDialog = true;
      await _showReplayPendingStopDialog(context, ref, next);
      ref.read(replayProvider.notifier).stop();
      _showingPendingStopDialog = false;
    });
  }

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
    final replaySessionActive = replayState.isRunning || replayState.isCompleted || replayState.nextTarget != null;

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

    List<DataPoint> buildDefaultReplayPoints(Duration duration) {
      final totalSeconds = duration.inMilliseconds / 1000.0;
      return List.generate(
        11,
        (index) => DataPoint(
          dataSetId: 'default-replay',
          tSeconds: totalSeconds * (index / 10),
          value: index,
        ),
      );
    }

    Future<void> startSelectedReplay() async {
      if (selectedSource == null) return;
      final targetSet = collectionCtrl.createReplayCollection(widget.containerId, selectedSource.id);
      if (targetSet == null) return;
      collectionCtrl.startWithExistingSet(targetSet);
      replayCtrl.startReplay(
        selectedSource,
        stretchFactor: factorFromSettings(selectedSource),
        interpolationEnabled: settings.replayInterpolationEnabled,
        sessionLabel: 'Replay measurement',
      );
    }

    Future<void> startDefaultReplay() async {
      final duration = Duration(seconds: settings.replayFixedDurationSeconds);
      final targetSet = collectionCtrl.createDefaultReplayCollection(widget.containerId, duration);
      if (targetSet == null) return;
      collectionCtrl.startWithExistingSet(targetSet);
      replayCtrl.startReplayFromPoints(
        buildDefaultReplayPoints(duration),
        stretchFactor: 1,
        interpolationEnabled: false,
        sessionLabel: 'Replay from default measurement',
      );
    }

    void handleReplayValueTap(int value) {
      if (!collectionState.isRunning) return;
      collectionCtrl.tapValue(value);
    }

    final countdownSeconds = replayState.nextTarget == null
        ? null
        : (replayState.nextTarget!.tSeconds * replayState.stretchFactor) -
            (replayState.elapsed.inMilliseconds / 1000.0);

    double replayProgress = 0.0;
    if (replayState.nextTarget != null &&
        replayState.currentTarget != null &&
        countdownSeconds != null) {
      final totalInterval =
          (replayState.nextTarget!.tSeconds - replayState.currentTarget!.tSeconds) *
              replayState.stretchFactor;
      if (totalInterval > 0) {
        replayProgress = (1.0 - countdownSeconds / totalInterval).clamp(0.0, 1.0);
      }
    }

    final isDarkLowLight = ref.watch(themeModeProvider) == ThemeMode.dark &&
        ref.watch(lowLightProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Replay'),
        backgroundColor: isDarkLowLight
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.8)
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Config section: hidden once replay starts ──────────────
            if (!replaySessionActive) ...[
              Row(
                children: [
                  const Expanded(child: Text('Choose data set to replay:')),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Starred only'),
                    selected: _starredOnly,
                    onSelected: (v) => setState(() => _starredOnly = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                isExpanded: true,
                value: visibleDataSets.any((s) => s.id == _selectedSourceId)
                    ? _selectedSourceId
                    : null,
                hint: const Text('Select data set'),
                items: visibleDataSets
                    .map((s) => DropdownMenuItem<String>(
                          value: s.id,
                          child: Text(
                              '${s.starred ? '★ ' : ''}${s.createdAt.toIso8601String().substring(0, 19)} - ${s.notes}'),
                        ))
                    .toList(),
                onChanged: (id) => setState(() => _selectedSourceId = id),
              ),
              if (selectedSource != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () =>
                        collectionCtrl.toggleSetStarred(selectedSource.id),
                    icon: Icon(selectedSource.starred
                        ? Icons.star
                        : Icons.star_border),
                    label: Text(
                        selectedSource.starred ? 'Unstar set' : 'Star set'),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: selectedSource == null ||
                            collectionState.isRunning ||
                            collectionState.isAwaitingNotes
                        ? null
                        : startSelectedReplay,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start replay collection'),
                  ),
                  ElevatedButton.icon(
                    onPressed: collectionState.isRunning ||
                            collectionState.isAwaitingNotes
                        ? null
                        : startDefaultReplay,
                    icon: const Icon(Icons.auto_graph),
                    label: const Text('Replay default 0→10'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: settings.replayInterpolationEnabled,
                onChanged: (v) =>
                    ref.read(containersProvider.notifier).updateSettings(
                          widget.containerId,
                          settings.copyWith(replayInterpolationEnabled: v),
                        ),
                title: const Text('Replay interpolation'),
                subtitle: const Text(
                    'Applies only to replaying an existing measurement.'),
              ),
              Row(
                children: [
                  const Text('Stretch mode: '),
                  DropdownButton<ReplayStretchMode>(
                    value: settings.replayStretchMode,
                    items: ReplayStretchMode.values
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      ref.read(containersProvider.notifier).updateSettings(
                            widget.containerId,
                            settings.copyWith(replayStretchMode: v),
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
                  onChanged: (v) =>
                      ref.read(containersProvider.notifier).updateSettings(
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
                          ref
                              .read(containersProvider.notifier)
                              .updateSettings(
                                widget.containerId,
                                settings.copyWith(
                                    replayFixedDurationSeconds: parsed),
                              );
                        },
                      ),
                    ),
                  ],
                ),
            ] else ...[
              // ── Active replay: only Finish button ─────────────────────
              ElevatedButton.icon(
                onPressed: collectionState.isRunning
                    ? () => collectionCtrl
                        .requestStop(MeasurementFinishReason.manual)
                    : null,
                icon: const Icon(Icons.stop),
                label: const Text('Finish measurement'),
              ),
            ],

            // ── Replay status visual (shown while active) ──────────────
            if (replaySessionActive) ...[
              const SizedBox(height: 12),
              Opacity(
                opacity: isDarkLowLight ? 0.5 : 1.0,
                child: _buildReplayStatusVisual(
                    context, replayState, container, replayProgress),
              ),
              const SizedBox(height: 4),
            ],

            const Divider(),
            MeasurementValueEntry(
              collectionState: collectionState,
              container: container,
              onTapValue: handleReplayValueTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplayStatusVisual(
    BuildContext context,
    ReplayState replayState,
    DataContainer container,
    double progress,
  ) {
    Widget valueCircle(int? value) {
      final bucket = value != null
          ? container.settings.buckets.where((b) => b.contains(value)).firstOrNull
          : null;
      final bgColor = bucket != null
          ? Color(bucket.color)
          : Theme.of(context).colorScheme.surfaceContainerHighest;
      final fgColor = bucket != null
          ? (bgColor.computeLuminance() > 0.4 ? Colors.black87 : Colors.white)
          : Theme.of(context).colorScheme.onSurface;
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        alignment: Alignment.center,
        child: Text(
          value?.toString() ?? '—',
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: fgColor),
        ),
      );
    }

    final barColor = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        valueCircle(replayState.currentTarget?.value),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: barColor,
                backgroundColor: barColor.withValues(alpha: 0.2),
              ),
            ),
          ),
        ),
        valueCircle(replayState.nextTarget?.value),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

