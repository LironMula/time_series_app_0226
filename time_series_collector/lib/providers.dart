import 'dart:async';

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

class CollectionState {
  final bool isRunning;
  final String? containerId;
  final DataSet? activeSet;
  final Duration elapsed;
  final int ignoredCues;

  const CollectionState({
    required this.isRunning,
    this.containerId,
    this.activeSet,
    this.elapsed = Duration.zero,
    this.ignoredCues = 0,
  });

  CollectionState copyWith({
    bool? isRunning,
    String? containerId,
    DataSet? activeSet,
    Duration? elapsed,
    int? ignoredCues,
  }) {
    return CollectionState(
      isRunning: isRunning ?? this.isRunning,
      containerId: containerId ?? this.containerId,
      activeSet: activeSet ?? this.activeSet,
      elapsed: elapsed ?? this.elapsed,
      ignoredCues: ignoredCues ?? this.ignoredCues,
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
  Timer? _timer;
  Duration _sinceLastPoint = Duration.zero;

  CollectionController(this._ref, this._repo) : super(CollectionState.initial());

  void _notifyDataSetChange() {
    _ref.read(dataSetRefreshProvider.notifier).state++;
  }

  void start(String containerId) {
    if (state.isRunning) return;
    final set = DataSet(containerId: containerId);
    _repo.addSet(set);
    _notifyDataSetChange();
    _startWithSet(containerId, set);
  }

  void startWithExistingSet(DataSet set) {
    if (state.isRunning) return;
    _startWithSet(set.containerId, set);
  }

  void _startWithSet(String containerId, DataSet set) {
    state = CollectionState(
      isRunning: true,
      containerId: containerId,
      activeSet: set,
      elapsed: Duration.zero,
      ignoredCues: 0,
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

  void _onTick(Timer t) {
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
      if (ignored >= 3) {
        stop();
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
    if (state.ignoredCues > 0) {
      state = state.copyWith(ignoredCues: 0);
    }
  }

  DataSet? createReplayCollection(String containerId, String sourceSetId) {
    if (state.isRunning) return null;
    final set = DataSet(containerId: containerId, notes: 'Replay of $sourceSetId');
    _repo.addSet(set);
    _notifyDataSetChange();
    return set;
  }

  void toggleSetStarred(String dataSetId) {
    _repo.toggleSetStarred(dataSetId);
    _notifyDataSetChange();
  }

  void stop({String? notes}) {
    if (!state.isRunning || state.activeSet == null) return;
    if (notes != null) {
      _repo.updateSet(state.activeSet!.copyWith(notes: notes));
      _notifyDataSetChange();
    }
    _timer?.cancel();
    _timer = null;
    state = CollectionState.initial();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
