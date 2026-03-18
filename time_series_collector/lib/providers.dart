import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'repositories.dart';

final containerRepoProvider = Provider<ContainerRepository>((ref) {
  return ContainerRepository();
});

final dataSetRepoProvider = Provider<DataSetRepository>((ref) {
  return DataSetRepository();
});

final containersProvider =
    StateNotifierProvider<ContainersNotifier, List<DataContainer>>((ref) {
  final repo = ref.read(containerRepoProvider);
  return ContainersNotifier(ref, repo);
});

class ContainersNotifier extends StateNotifier<List<DataContainer>> {
  final Ref _ref;
  final ContainerRepository _repo;

  ContainersNotifier(this._ref, this._repo) : super(_repo.getAll());

  void create(String name, {ContainerSettings? settings}) {
    final c = DataContainer(name: name, settings: settings);
    _repo.add(c);
    state = _repo.getAll();
  }

  void rename(String id, String name) {
    final c = state.firstWhere((c) => c.id == id);
    _repo.update(c.copyWith(name: name));
    state = _repo.getAll();
  }

  void importAll(List<DataContainer> containers) {
    _repo.replaceAll(containers);
    state = _repo.getAll();
  }

  void remove(String id) {
    _repo.remove(id);
    _ref.read(dataSetRepoProvider).removeByContainer(id);
    state = _repo.getAll();
  }

  void updateSettings(String id, ContainerSettings settings) {
    final c = state.firstWhere((c) => c.id == id);
    _repo.update(c.copyWith(settings: settings));
    state = _repo.getAll();
  }
}

final selectedContainerIdProvider = StateProvider<String?>((ref) => null);

final dataSetRefreshProvider = StateProvider<int>((ref) => 0);

final dataSetsProvider = Provider.family<List<DataSet>, String>((ref, containerId) {
  ref.watch(dataSetRefreshProvider);
  final repo = ref.watch(dataSetRepoProvider);
  return repo.getByContainer(containerId);
});

class CollectionStartConfig {
  final bool assistedEnabled;
  final int assistedDtSeconds;
  final CueType cueType;

  const CollectionStartConfig({
    required this.assistedEnabled,
    required this.assistedDtSeconds,
    required this.cueType,
  });

  factory CollectionStartConfig.fromSettings(ContainerSettings settings) =>
      CollectionStartConfig(
        assistedEnabled: settings.assistedEnabled,
        assistedDtSeconds: settings.assistedDt.inSeconds,
        cueType: settings.cueType,
      );
}

enum MeasurementFinishReason { manual, stopAtTen, ignoredReminders }

class CollectionState {
  final bool isRunning;
  final String? containerId;
  final DataSet? activeSet;
  final Duration elapsed;
  final int ignoredCues;
  final int? currentValue;
  final bool isAwaitingNotes;
  final MeasurementFinishReason? finishReason;
  final bool stopDialogClaimed;

  const CollectionState({
    required this.isRunning,
    this.containerId,
    this.activeSet,
    this.elapsed = Duration.zero,
    this.ignoredCues = 0,
    this.currentValue,
    this.isAwaitingNotes = false,
    this.finishReason,
    this.stopDialogClaimed = false,
  });

  CollectionState copyWith({
    bool? isRunning,
    String? containerId,
    DataSet? activeSet,
    Duration? elapsed,
    int? ignoredCues,
    int? currentValue,
    bool clearCurrentValue = false,
    bool? isAwaitingNotes,
    MeasurementFinishReason? finishReason,
    bool clearFinishReason = false,
    bool? stopDialogClaimed,
  }) {
    return CollectionState(
      isRunning: isRunning ?? this.isRunning,
      containerId: containerId ?? this.containerId,
      activeSet: activeSet ?? this.activeSet,
      elapsed: elapsed ?? this.elapsed,
      ignoredCues: ignoredCues ?? this.ignoredCues,
      currentValue: clearCurrentValue ? null : (currentValue ?? this.currentValue),
      isAwaitingNotes: isAwaitingNotes ?? this.isAwaitingNotes,
      finishReason: clearFinishReason ? null : (finishReason ?? this.finishReason),
      stopDialogClaimed: stopDialogClaimed ?? this.stopDialogClaimed,
    );
  }

  factory CollectionState.initial() => const CollectionState(isRunning: false);
}

final collectionProvider =
    StateNotifierProvider<CollectionController, CollectionState>((ref) {
  final dataRepo = ref.read(dataSetRepoProvider);
  return CollectionController(ref, dataRepo);
});

class CollectionController extends StateNotifier<CollectionState> {
  final Ref _ref;
  final DataSetRepository _repo;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _timer;
  Duration _sinceLastPoint = Duration.zero;

  CollectionController(this._ref, this._repo) : super(CollectionState.initial());

  void _notifyDataSetChange() {
    _ref.read(dataSetRefreshProvider.notifier).state++;
  }

  void start(String containerId) {
    if (state.isRunning || state.isAwaitingNotes) return;
    final set = DataSet(containerId: containerId);
    _repo.addSet(set);
    _notifyDataSetChange();
    _startWithSet(containerId, set);
  }

  void startWithExistingSet(DataSet set) {
    if (state.isRunning || state.isAwaitingNotes) return;
    _startWithSet(set.containerId, set);
  }

  void _startWithSet(String containerId, DataSet set) {
    _repo.addPoint(
      DataPoint(
        dataSetId: set.id,
        tSeconds: 0,
        value: 0,
      ),
    );
    state = CollectionState(
      isRunning: true,
      containerId: containerId,
      activeSet: set,
      elapsed: Duration.zero,
      ignoredCues: 0,
      currentValue: 0,
      isAwaitingNotes: false,
      finishReason: null,
      stopDialogClaimed: false,
    );
    _sinceLastPoint = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  void applyStartConfig(String containerId, CollectionStartConfig config) {
    final container = _ref.read(containerRepoProvider).getById(containerId);
    if (container == null) return;
    final updatedSettings = container.settings.copyWith(
      assistedEnabled: config.assistedEnabled,
      assistedDt: Duration(seconds: config.assistedDtSeconds),
      cueType: config.cueType,
    );
    _ref.read(containersProvider.notifier).updateSettings(containerId, updatedSettings);
  }

  Future<void> _emitCue(CueType cueType) async {
    switch (cueType) {
      case CueType.beep:
        await _audioPlayer.stop();
        await _audioPlayer.play(BytesSource(_buildSineWaveWav()));
        return;
      case CueType.flashlight:
        return;
    }
  }

  Uint8List _buildSineWaveWav({
    double frequencyHz = 880,
    int durationMs = 250,
    int sampleRate = 44100,
  }) {
    final sampleCount = (sampleRate * durationMs / 1000).round();
    final dataLength = sampleCount * 2;
    final byteData = ByteData(44 + dataLength);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        byteData.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    byteData.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    byteData.setUint32(40, dataLength, Endian.little);

    const amplitude = 0.5;
    for (var i = 0; i < sampleCount; i++) {
      final envelope = 1 - (i / sampleCount);
      final sample = sin(2 * pi * frequencyHz * (i / sampleRate));
      final value = (sample * 32767 * amplitude * envelope).round();
      byteData.setInt16(44 + (i * 2), value, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  Future<void> _onTick(Timer t) async {
    if (!state.isRunning) return;
    final newElapsed = state.elapsed + const Duration(seconds: 1);
    _sinceLastPoint += const Duration(seconds: 1);
    state = state.copyWith(elapsed: newElapsed);

    final container = _ref
        .read(containersProvider)
        .firstWhere((c) => c.id == state.containerId);
    final settings = container.settings;

    if (!settings.assistedEnabled) return;

    if (_sinceLastPoint >= settings.assistedDt) {
      _sinceLastPoint = Duration.zero;
      final ignored = state.ignoredCues + 1;
      state = state.copyWith(ignoredCues: ignored);
      await _emitCue(settings.cueType);
      if (ignored >= 3) {
        requestStop(MeasurementFinishReason.ignoredReminders);
      }
    }
  }

  void tapValue(int value) {
    if (!state.isRunning || state.activeSet == null) return;
    final p = DataPoint(
      dataSetId: state.activeSet!.id,
      tSeconds: state.elapsed.inMilliseconds / 1000.0,
      value: value,
    );
    _repo.addPoint(p);
    _sinceLastPoint = Duration.zero;

    final container = _ref.read(containerRepoProvider).getById(state.containerId!);
    final shouldStopAtTen = container?.settings.stopMeasurementOnTen == true && value == 10;

    state = state.copyWith(
      ignoredCues: 0,
      currentValue: value,
    );

    if (shouldStopAtTen) {
      requestStop(MeasurementFinishReason.stopAtTen);
    }
  }

  DataSet? createReplayCollection(String containerId, String sourceSetId) {
    if (state.isRunning || state.isAwaitingNotes) return null;
    final set = DataSet(containerId: containerId, notes: 'Replay of $sourceSetId');
    _repo.addSet(set);
    _notifyDataSetChange();
    return set;
  }

  DataSet? createDefaultReplayCollection(String containerId, Duration duration) {
    if (state.isRunning || state.isAwaitingNotes) return null;
    final set = DataSet(
      containerId: containerId,
      notes: 'Replay of default measurement (${duration.inSeconds}s)',
    );
    _repo.addSet(set);
    _notifyDataSetChange();
    return set;
  }

  void requestStop(MeasurementFinishReason reason) {
    if ((!state.isRunning && !state.isAwaitingNotes) || state.activeSet == null) return;
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(
      isRunning: false,
      isAwaitingNotes: true,
      finishReason: reason,
      stopDialogClaimed: false,
    );
  }


  bool claimPendingStopDialog() {
    if (!state.isAwaitingNotes || state.stopDialogClaimed) return false;
    state = state.copyWith(stopDialogClaimed: true);
    return true;
  }

  void toggleSetStarred(String dataSetId) {
    _repo.toggleSetStarred(dataSetId);
    _notifyDataSetChange();
  }

  void finalizeStop({String? notes}) {
    if (state.activeSet == null) return;
    final noteText = notes?.trim();
    if (noteText != null && noteText.isNotEmpty) {
      _repo.updateSet(state.activeSet!.copyWith(notes: noteText));
      _notifyDataSetChange();
    }
    _timer?.cancel();
    _timer = null;
    state = CollectionState.initial();
  }

  void cancelPendingStop() {
    if (!state.isAwaitingNotes) return;
    finalizeStop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
