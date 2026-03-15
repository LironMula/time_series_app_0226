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
    final sets = repo.getByContainer(containerId).where((s) {
      return s.startTime.isBefore(periodEnd) &&
          s.startTime.isAfter(periodStart.subtract(const Duration(days: 365)));
    }).toList();

    if (sets.isEmpty) return [];

    final results = <IntervalBucketResult>[];

    DateTime cursor = periodStart;
    while (cursor.isBefore(periodEnd)) {
      final intervalEnd = cursor.add(interval);
      final secondsPerBucket = {
        for (final b in buckets) b: 0.0,
      };

      final contributingSets = sets.where((s) {
        final points = repo.getPoints(s.id);
        if (points.isEmpty) return false;
        final absStart = s.startTime;
        final absEnd = absStart.add(
          Duration(
            milliseconds:
                (points.last.tSeconds * 1000).round(),
          ),
        );
        return absEnd.isAfter(cursor) && absStart.isBefore(intervalEnd);
      }).toList();

      if (contributingSets.isEmpty) {
        results.add(IntervalBucketResult(
          intervalStart: cursor,
          secondsPerBucket: secondsPerBucket,
        ));
        cursor = intervalEnd;
        continue;
      }

      for (final set in contributingSets) {
        final points = repo.getPoints(set.id);
        if (points.isEmpty) continue;

        for (int i = 0; i < points.length - 1; i++) {
          final p1 = points[i];
          final p2 = points[i + 1];

          final absT1 = set.startTime.add(
            Duration(milliseconds: (p1.tSeconds * 1000).round()),
          );
          final absT2 = set.startTime.add(
            Duration(milliseconds: (p2.tSeconds * 1000).round()),
          );

          final segStart = absT1.isBefore(cursor) ? cursor : absT1;
          final segEnd =
              absT2.isAfter(intervalEnd) ? intervalEnd : absT2;

          if (!segEnd.isAfter(segStart)) continue;

          final seconds =
              segEnd.difference(segStart).inMilliseconds / 1000.0;

          final bucket = _bucketForValue(buckets, p1.value);
          if (bucket != null) {
            secondsPerBucket[bucket] =
                (secondsPerBucket[bucket] ?? 0) + seconds;
          }
        }
      }

      final divisor = contributingSets.length;
      if (divisor > 1) {
        for (final b in buckets) {
          secondsPerBucket[b] =
              (secondsPerBucket[b] ?? 0) / divisor;
        }
      }

      results.add(IntervalBucketResult(
        intervalStart: cursor,
        secondsPerBucket: secondsPerBucket,
      ));
      cursor = intervalEnd;
    }

    return results;
  }

  ValueBucket? _bucketForValue(
      List<ValueBucket> buckets, int value) {
    for (final b in buckets) {
      if (b.contains(value)) return b;
    }
    return null;
  }
}
