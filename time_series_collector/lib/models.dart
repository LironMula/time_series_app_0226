import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

class ValueBucket {
  final int minInclusive;
  final int maxInclusive;
  final int color; // ARGB int

  const ValueBucket({
    required this.minInclusive,
    required this.maxInclusive,
    required this.color,
  });

  bool contains(int v) =>
      v >= minInclusive && v <= maxInclusive;
}

class ContainerSettings {
  final Duration assistedDt;
  final bool assistedEnabled;
  final CueType cueType;
  final List<ValueBucket> buckets;

  const ContainerSettings({
    required this.assistedDt,
    required this.assistedEnabled,
    required this.cueType,
    required this.buckets,
  });

  ContainerSettings copyWith({
    Duration? assistedDt,
    bool? assistedEnabled,
    CueType? cueType,
    List<ValueBucket>? buckets,
  }) {
    return ContainerSettings(
      assistedDt: assistedDt ?? this.assistedDt,
      assistedEnabled: assistedEnabled ?? this.assistedEnabled,
      cueType: cueType ?? this.cueType,
      buckets: buckets ?? this.buckets,
    );
  }

  factory ContainerSettings.defaultSettings() {
    return ContainerSettings(
      assistedDt: const Duration(seconds: 10),
      assistedEnabled: false,
      cueType: CueType.beep,
      buckets: const [
        ValueBucket(minInclusive: 0, maxInclusive: 3, color: 0xFF4CAF50),
        ValueBucket(minInclusive: 4, maxInclusive: 5, color: 0xFF2196F3),
        ValueBucket(minInclusive: 6, maxInclusive: 7, color: 0xFFFFC107),
        ValueBucket(minInclusive: 8, maxInclusive: 8, color: 0xFFFF9800),
        ValueBucket(minInclusive: 9, maxInclusive: 10, color: 0xFFF44336),
      ],
    );
  }
}

enum CueType { beep, flashlight }

class DataContainer {
  final String id;
  final String name;
  final DateTime createdAt;
  final ContainerSettings settings;

  DataContainer({
    String? id,
    required this.name,
    DateTime? createdAt,
    ContainerSettings? settings,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        settings = settings ?? ContainerSettings.defaultSettings();

  DataContainer copyWith({
    String? name,
    ContainerSettings? settings,
  }) {
    return DataContainer(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      settings: settings ?? this.settings,
    );
  }
}

class DataSet {
  final String id;
  final String containerId;
  final DateTime createdAt;
  final DateTime startTime;
  final String notes;

  DataSet({
    String? id,
    required this.containerId,
    DateTime? createdAt,
    DateTime? startTime,
    this.notes = '',
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        startTime = startTime ?? DateTime.now();

  DataSet copyWith({String? notes}) {
    return DataSet(
      id: id,
      containerId: containerId,
      createdAt: createdAt,
      startTime: startTime,
      notes: notes ?? this.notes,
    );
  }
}

class DataPoint {
  final String id;
  final String dataSetId;
  final double tSeconds;
  final int value;

  DataPoint({
    String? id,
    required this.dataSetId,
    required this.tSeconds,
    required this.value,
  }) : id = id ?? newId();
}
