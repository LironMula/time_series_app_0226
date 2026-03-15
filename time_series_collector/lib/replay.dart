import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';
import 'repositories.dart';

class ReplayState {
  final bool isRunning;
  final DataSet? sourceSet;
  final Duration elapsed;
  final DataPoint? nextTarget;
  final double stretchFactor;
  final bool interpolationEnabled;

  const ReplayState({
    required this.isRunning,
    this.sourceSet,
    this.elapsed = Duration.zero,
    this.nextTarget,
    this.stretchFactor = 1.0,
    this.interpolationEnabled = false,
  });

  ReplayState copyWith({
    bool? isRunning,
    DataSet? sourceSet,
    Duration? elapsed,
    DataPoint? nextTarget,
    double? stretchFactor,
    bool? interpolationEnabled,
  }) {
    return ReplayState(
      isRunning: isRunning ?? this.isRunning,
      sourceSet: sourceSet ?? this.sourceSet,
      elapsed: elapsed ?? this.elapsed,
      nextTarget: nextTarget ?? this.nextTarget,
      stretchFactor: stretchFactor ?? this.stretchFactor,
      interpolationEnabled: interpolationEnabled ?? this.interpolationEnabled,
    );
  }

  factory ReplayState.initial() => const ReplayState(isRunning: false);
}

final replayProvider = StateNotifierProvider<ReplayController, ReplayState>((ref) {
  final dsRepo = ref.read(dataSetRepoProvider);
  return ReplayController(dsRepo);
});

class ReplayController extends StateNotifier<ReplayState> {
  final DataSetRepository _repo;
  Timer? _timer;
  List<DataPoint> _points = [];

  ReplayController(this._repo) : super(ReplayState.initial());

  void startReplay(
    DataSet source, {
    required double stretchFactor,
    required bool interpolationEnabled,
  }) {
    if (state.isRunning) stop();
    final rawPoints = _repo.getPoints(source.id);
    if (rawPoints.isEmpty) return;

    _points = interpolationEnabled ? _interpolate(rawPoints) : rawPoints;
    _points.sort((a, b) => a.tSeconds.compareTo(b.tSeconds));

    state = ReplayState(
      isRunning: true,
      sourceSet: source,
      elapsed: Duration.zero,
      nextTarget: _points.first,
      stretchFactor: stretchFactor,
      interpolationEnabled: interpolationEnabled,
    );

    _timer = Timer.periodic(const Duration(milliseconds: 200), _onTick);
  }

  void _onTick(Timer t) {
    if (!state.isRunning || state.sourceSet == null || _points.isEmpty) {
      return;
    }

    final newElapsed = state.elapsed + const Duration(milliseconds: 200);
    final stretchedTime = (newElapsed.inMilliseconds / 1000.0) / state.stretchFactor;

    final next = _points.firstWhere(
      (p) => p.tSeconds >= stretchedTime,
      orElse: () => _points.last,
    );

    state = state.copyWith(elapsed: newElapsed, nextTarget: next);

    if (stretchedTime >= _points.last.tSeconds) {
      stop();
    }
  }

  List<DataPoint> _interpolate(List<DataPoint> source) {
    final result = <DataPoint>[];
    for (int i = 0; i < source.length; i++) {
      final current = source[i];
      result.add(current);
      if (i == source.length - 1) continue;
      final next = source[i + 1];
      final valueDelta = next.value - current.value;
      final steps = valueDelta.abs();
      if (steps <= 1) continue;

      final dt = (next.tSeconds - current.tSeconds) / steps;
      final direction = valueDelta.sign;
      for (int k = 1; k < steps; k++) {
        result.add(
          DataPoint(
            dataSetId: current.dataSetId,
            tSeconds: current.tSeconds + (dt * k),
            value: current.value + (direction * k),
          ),
        );
      }
    }
    return result;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    state = ReplayState.initial();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
