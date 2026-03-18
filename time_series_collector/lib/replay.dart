import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';
import 'repositories.dart';

class ReplayState {
  final bool isRunning;
  final bool isCompleted;
  final DataSet? sourceSet;
  final Duration elapsed;
  final DataPoint? currentTarget;
  final DataPoint? nextTarget;
  final double stretchFactor;
  final bool interpolationEnabled;
  final String sessionLabel;

  const ReplayState({
    required this.isRunning,
    required this.isCompleted,
    this.sourceSet,
    this.elapsed = Duration.zero,
    this.currentTarget,
    this.nextTarget,
    this.stretchFactor = 1.0,
    this.interpolationEnabled = false,
    this.sessionLabel = 'Replay measurement',
  });

  ReplayState copyWith({
    bool? isRunning,
    bool? isCompleted,
    DataSet? sourceSet,
    Duration? elapsed,
    DataPoint? currentTarget,
    bool clearCurrentTarget = false,
    DataPoint? nextTarget,
    bool clearNextTarget = false,
    double? stretchFactor,
    bool? interpolationEnabled,
    String? sessionLabel,
  }) {
    return ReplayState(
      isRunning: isRunning ?? this.isRunning,
      isCompleted: isCompleted ?? this.isCompleted,
      sourceSet: sourceSet ?? this.sourceSet,
      elapsed: elapsed ?? this.elapsed,
      currentTarget: clearCurrentTarget ? null : (currentTarget ?? this.currentTarget),
      nextTarget: clearNextTarget ? null : (nextTarget ?? this.nextTarget),
      stretchFactor: stretchFactor ?? this.stretchFactor,
      interpolationEnabled: interpolationEnabled ?? this.interpolationEnabled,
      sessionLabel: sessionLabel ?? this.sessionLabel,
    );
  }

  factory ReplayState.initial() => const ReplayState(isRunning: false, isCompleted: false);
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
    String? sessionLabel,
  }) {
    final rawPoints = _repo.getPoints(source.id);
    startReplayFromPoints(
      rawPoints,
      sourceSet: source,
      stretchFactor: stretchFactor,
      interpolationEnabled: interpolationEnabled,
      sessionLabel: sessionLabel ?? 'Replay measurement',
    );
  }

  void startReplayFromPoints(
    List<DataPoint> rawPoints, {
    DataSet? sourceSet,
    required double stretchFactor,
    required bool interpolationEnabled,
    required String sessionLabel,
  }) {
    if (state.isRunning) stop();
    if (rawPoints.isEmpty) return;

    _points = interpolationEnabled ? _interpolate(rawPoints) : List<DataPoint>.from(rawPoints);
    _points.sort((a, b) => a.tSeconds.compareTo(b.tSeconds));
    final current = _currentPointFor(0);
    final next = _nextPointAfter(0);

    state = ReplayState(
      isRunning: true,
      isCompleted: false,
      sourceSet: sourceSet,
      elapsed: Duration.zero,
      currentTarget: current,
      nextTarget: next,
      stretchFactor: stretchFactor,
      interpolationEnabled: interpolationEnabled,
      sessionLabel: sessionLabel,
    );

    _timer = Timer.periodic(const Duration(milliseconds: 200), _onTick);
  }

  DataPoint _currentPointFor(double stretchedTimeSeconds) {
    var current = _points.first;
    for (final point in _points) {
      if (point.tSeconds > stretchedTimeSeconds) {
        break;
      }
      current = point;
    }
    return current;
  }

  DataPoint? _nextPointAfter(double stretchedTimeSeconds) {
    for (final point in _points) {
      if (point.tSeconds > stretchedTimeSeconds) {
        return point;
      }
    }
    return null;
  }

  void _onTick(Timer t) {
    if (!state.isRunning || _points.isEmpty) {
      return;
    }

    final newElapsed = state.elapsed + const Duration(milliseconds: 200);
    final stretchedTime = (newElapsed.inMilliseconds / 1000.0) / state.stretchFactor;

    if (stretchedTime >= _points.last.tSeconds) {
      _timer?.cancel();
      _timer = null;
      state = state.copyWith(
        elapsed: newElapsed,
        currentTarget: _points.last,
        isRunning: false,
        isCompleted: true,
        clearNextTarget: true,
      );
      return;
    }

    state = state.copyWith(
      elapsed: newElapsed,
      currentTarget: _currentPointFor(stretchedTime),
      nextTarget: _nextPointAfter(stretchedTime),
      isCompleted: false,
    );
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
    _points = [];
    state = ReplayState.initial();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
