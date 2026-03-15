import 'models.dart';
import 'repositories.dart';

class IntervalBucketResult {
  final DateTime intervalStart;
  final Map<ValueBucket, double> secondsPerBucket;

  IntervalBucketResult({
    required this.intervalStart,
    required this.secondsPerBucket,
  });
}

class HistogramAggregator {
  final DataSetRepository repo;

  HistogramAggregator(this.repo);

  List<IntervalBucketResult> aggregate({
    required String containerId,
    required List<ValueBucket> buckets,
    required DateTime periodStart,
    required DateTime periodEnd,
    required Duration interval,
  }) {
    final sets = repo.getByContainer(containerId);
    final results = <IntervalBucketResult>[];

    DateTime cursor = periodStart;
    while (cursor.isBefore(periodEnd)) {
      final intervalEnd = cursor.add(interval);
      final secondsPerBucket = {for (final b in buckets) b: 0.0};

      final contributingSets = sets.where((set) {
        final points = repo.getPoints(set.id);
        if (points.length < 2) return false;
        final absEnd = set.startTime.add(Duration(milliseconds: (points.last.tSeconds * 1000).round()));
        return absEnd.isAfter(cursor) && set.startTime.isBefore(intervalEnd);
      }).toList();

      for (final set in contributingSets) {
        final points = repo.getPoints(set.id);
        final secMap = _sampleSetIntoBuckets(
          points: points,
          setStart: set.startTime,
          intervalStart: cursor,
          intervalEnd: intervalEnd,
          buckets: buckets,
        );
        for (final b in buckets) {
          secondsPerBucket[b] = (secondsPerBucket[b] ?? 0) + (secMap[b] ?? 0);
        }
      }

      if (contributingSets.isNotEmpty) {
        for (final b in buckets) {
          secondsPerBucket[b] = (secondsPerBucket[b] ?? 0) / contributingSets.length;
        }
      }

      results.add(IntervalBucketResult(intervalStart: cursor, secondsPerBucket: secondsPerBucket));
      cursor = intervalEnd;
    }

    return results;
  }

  Map<ValueBucket, double> _sampleSetIntoBuckets({
    required List<DataPoint> points,
    required DateTime setStart,
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required List<ValueBucket> buckets,
  }) {
    final out = {for (final b in buckets) b: 0.0};
    if (points.length < 2) return out;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final absT1 = setStart.add(Duration(milliseconds: (p1.tSeconds * 1000).round()));
      final absT2 = setStart.add(Duration(milliseconds: (p2.tSeconds * 1000).round()));

      final segStart = absT1.isBefore(intervalStart) ? intervalStart : absT1;
      final segEnd = absT2.isAfter(intervalEnd) ? intervalEnd : absT2;
      if (!segEnd.isAfter(segStart)) continue;

      double secondCursor = 0;
      final segmentSeconds = segEnd.difference(segStart).inMilliseconds / 1000.0;
      final fullSegmentSeconds = absT2.difference(absT1).inMilliseconds / 1000.0;
      if (fullSegmentSeconds <= 0) continue;

      while (secondCursor < segmentSeconds) {
        final sampleTime = segStart.add(Duration(milliseconds: (secondCursor * 1000).round()));
        final elapsedFromP1 = sampleTime.difference(absT1).inMilliseconds / 1000.0;
        final ratio = (elapsedFromP1 / fullSegmentSeconds).clamp(0.0, 1.0);
        final interpolatedValue = p1.value + ((p2.value - p1.value) * ratio);
        final roundedValue = interpolatedValue.round().clamp(0, 10) as int;
        final bucket = _bucketForValue(buckets, roundedValue);
        if (bucket != null) {
          out[bucket] = (out[bucket] ?? 0) + 1;
        }
        secondCursor += 1;
      }
    }
    return out;
  }

  ValueBucket? _bucketForValue(List<ValueBucket> buckets, int value) {
    for (final b in buckets) {
      if (b.contains(value)) return b;
    }
    return null;
  }
}
