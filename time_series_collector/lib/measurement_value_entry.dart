import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';

/// Shared value-entry panel used by both the collection tab and replay page.
/// Contains the status text (elapsed, current value) and the styled number
/// buttons (0–10). All low-light / dark-mode effects are handled here so
/// any future visual change automatically applies to both features.
class MeasurementValueEntry extends ConsumerWidget {
  final CollectionState collectionState;
  final DataContainer container;
  final void Function(int value) onTapValue;

  const MeasurementValueEntry({
    super.key,
    required this.collectionState,
    required this.container,
    required this.onTapValue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkLowLight = ref.watch(themeModeProvider) == ThemeMode.dark &&
        ref.watch(lowLightProvider);
    final buttonOpacity = !isDarkLowLight
        ? 1.0
        : (collectionState.ignoredCues >= 1 ? 0.5 : 0.3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: isDarkLowLight ? 0.5 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Elapsed: ${collectionState.elapsed.inSeconds}s'
                ' | ignored cues: ${collectionState.ignoredCues}',
              ),
              const SizedBox(height: 4),
              Text(
                'Current value: ${collectionState.currentValue?.toString() ?? '—'}',
              ),
              if (container.settings.stopMeasurementOnTen)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Tapping value 10 records the point and ends the measurement.',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: buttonOpacity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(11, (i) {
              final bucket = container.settings.buckets
                  .where((b) => b.contains(i))
                  .firstOrNull;
              final bgColor = bucket != null ? Color(bucket.color) : null;
              final fgColor = bgColor != null
                  ? (bgColor.computeLuminance() > 0.4
                      ? Colors.black87
                      : Colors.white)
                  : null;
              return SizedBox(
                width: 72,
                height: 72,
                child: ElevatedButton(
                  onPressed: collectionState.isRunning
                      ? () => onTapValue(i)
                      : null,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: bgColor,
                    foregroundColor: fgColor,
                    disabledBackgroundColor: bgColor?.withValues(alpha: 0.4),
                  ),
                  child: Text(
                    '$i',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
