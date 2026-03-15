import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'repositories.dart';
import 'providers.dart';

class ReplayState {
  final bool isRunning;
  final DataSet? sourceSet;
  final double stretchFactor; // 0.5 - 2.0
  final Duration elapsed;
  final DataPoint? nextTarget;

  const ReplayState({
    required this.isRunning,
    this.sourceSet,
    this.stretchFactor = 1.0,
    this.elapsed = Duration.zero,
    this.nextTarget,
  });

  ReplayState copyWith({
    bool? isRunning,
    DataSet? sourceSet,
    double? stretchFactor,
    Duration? elapsed,
    DataPoint? nextTarget,
  }) {
    return ReplayState(
      isRunning: isRunning ?? this.isRunning,
      sourceSet: sourceSet ?? this.sourceSet,
      stretchFactor: stretchFactor ?? this.stretchFactor,
      elapsed: elapsed ?? this.elapsed,
      nextTarget: nextTarget ?? this.nextTarget,
    );
  }

  factory ReplayState.initial() => const ReplayState(isRunning: false);
}

final replayProvider =
    StateNotifierProvider<ReplayController, ReplayState>((ref) {
  final dsRepo = ref.read(dataSetRepoProvider);
  return ReplayController(ref, dsRepo);
});

class ReplayController extends StateNotifier<ReplayState> {
  final Ref _ref;
  final DataSetRepository _repo;
  Timer? _timer;
  List<DataPoint> _points = [];

  ReplayController(this._ref, this._repo) : super(ReplayState.initial());

  void startReplay(DataSet source, {double stretchFactor = 1.0}) {
    if (state.isRunning) stop();
    _points = _repo.getPoints(source.id);
    if (_points.isEmpty) return;

    _points.sort((a, b) => a.tSeconds.compareTo(b.tSeconds));

    state = ReplayState(
      isRunning: true,
      sourceSet: source,
      stretchFactor: stretchFactor,
      elapsed: Duration.zero,
      nextTarget: _points.first,
    );

    _timer = Timer.periodic(const Duration(milliseconds: 200), _onTick);
  }

  void _onTick(Timer t) {
    if (!state.isRunning || state.sourceSet == null || _points.isEmpty) {
      return;
    }

    final newElapsed =
        state.elapsed + const Duration(milliseconds: 200);
    state = state.copyWith(elapsed: newElapsed);

    final scaledSeconds = newElapsed.inMilliseconds / 1000.0;
    final stretchedTime =
        scaledSeconds / state.stretchFactor; // t' = t / k

    final next = _points.firstWhere(
      (p) => p.tSeconds >= stretchedTime,
      orElse: () => _points.last,
    );

    state = state.copyWith(nextTarget: next);

    if (stretchedTime >= _points.last.tSeconds) {
      stop();
    }
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
