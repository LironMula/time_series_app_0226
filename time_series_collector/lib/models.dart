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

  bool contains(int v) => v >= minInclusive && v <= maxInclusive;

  Map<String, dynamic> toJson() => {
        'minInclusive': minInclusive,
        'maxInclusive': maxInclusive,
        'color': color,
      };

  factory ValueBucket.fromJson(Map<String, dynamic> json) => ValueBucket(
        minInclusive: json['minInclusive'] as int,
        maxInclusive: json['maxInclusive'] as int,
        color: json['color'] as int,
      );

  String get label => '$minInclusive-$maxInclusive';
}

enum CueType { beep, flashlight, vibration }

enum ReplayStretchMode { factor, fixedDuration }

class ContainerSettings {
  final Duration assistedDt;
  final bool assistedEnabled;
  final CueType cueType;
  final List<ValueBucket> buckets;
  final bool replayInterpolationEnabled;
  final ReplayStretchMode replayStretchMode;
  final double replayStretchFactor;
  final int replayFixedDurationSeconds;
  final bool stopMeasurementOnTen;

  const ContainerSettings({
    required this.assistedDt,
    required this.assistedEnabled,
    required this.cueType,
    required this.buckets,
    required this.replayInterpolationEnabled,
    required this.replayStretchMode,
    required this.replayStretchFactor,
    required this.replayFixedDurationSeconds,
    required this.stopMeasurementOnTen,
  });

  ContainerSettings copyWith({
    Duration? assistedDt,
    bool? assistedEnabled,
    CueType? cueType,
    List<ValueBucket>? buckets,
    bool? replayInterpolationEnabled,
    ReplayStretchMode? replayStretchMode,
    double? replayStretchFactor,
    int? replayFixedDurationSeconds,
    bool? stopMeasurementOnTen,
  }) {
    return ContainerSettings(
      assistedDt: assistedDt ?? this.assistedDt,
      assistedEnabled: assistedEnabled ?? this.assistedEnabled,
      cueType: cueType ?? this.cueType,
      buckets: buckets ?? this.buckets,
      replayInterpolationEnabled:
          replayInterpolationEnabled ?? this.replayInterpolationEnabled,
      replayStretchMode: replayStretchMode ?? this.replayStretchMode,
      replayStretchFactor: replayStretchFactor ?? this.replayStretchFactor,
      replayFixedDurationSeconds:
          replayFixedDurationSeconds ?? this.replayFixedDurationSeconds,
      stopMeasurementOnTen:
          stopMeasurementOnTen ?? this.stopMeasurementOnTen,
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
      replayInterpolationEnabled: false,
      replayStretchMode: ReplayStretchMode.factor,
      replayStretchFactor: 1.0,
      replayFixedDurationSeconds: 60,
      stopMeasurementOnTen: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'assistedDtSeconds': assistedDt.inSeconds,
        'assistedEnabled': assistedEnabled,
        'cueType': cueType.name,
        'buckets': buckets.map((b) => b.toJson()).toList(),
        'replayInterpolationEnabled': replayInterpolationEnabled,
        'replayStretchMode': replayStretchMode.name,
        'replayStretchFactor': replayStretchFactor,
        'replayFixedDurationSeconds': replayFixedDurationSeconds,
        'stopMeasurementOnTen': stopMeasurementOnTen,
      };

  factory ContainerSettings.fromJson(Map<String, dynamic> json) => ContainerSettings(
        assistedDt: Duration(seconds: json['assistedDtSeconds'] as int? ?? 10),
        assistedEnabled: json['assistedEnabled'] as bool? ?? false,
        cueType: CueType.values.byName(json['cueType'] as String? ?? 'beep'),
        buckets: ((json['buckets'] as List?) ?? const [])
            .map((e) => ValueBucket.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        replayInterpolationEnabled:
            json['replayInterpolationEnabled'] as bool? ?? false,
        replayStretchMode: ReplayStretchMode.values
            .byName(json['replayStretchMode'] as String? ?? 'factor'),
        replayStretchFactor: (json['replayStretchFactor'] as num?)?.toDouble() ?? 1.0,
        replayFixedDurationSeconds:
            json['replayFixedDurationSeconds'] as int? ?? 60,
        stopMeasurementOnTen: json['stopMeasurementOnTen'] as bool? ?? false,
      );
}

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'settings': settings.toJson(),
      };

  factory DataContainer.fromJson(Map<String, dynamic> json) => DataContainer(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        settings: ContainerSettings.fromJson(
          (json['settings'] as Map).cast<String, dynamic>(),
        ),
      );
}

class DataSet {
  final String id;
  final String containerId;
  final DateTime createdAt;
  final DateTime startTime;
  final String notes;
  final bool starred;

  DataSet({
    String? id,
    required this.containerId,
    DateTime? createdAt,
    DateTime? startTime,
    this.notes = '',
    this.starred = false,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        startTime = startTime ?? DateTime.now();

  DataSet copyWith({String? notes, bool? starred}) {
    return DataSet(
      id: id,
      containerId: containerId,
      createdAt: createdAt,
      startTime: startTime,
      notes: notes ?? this.notes,
      starred: starred ?? this.starred,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'containerId': containerId,
        'createdAt': createdAt.toIso8601String(),
        'startTime': startTime.toIso8601String(),
        'notes': notes,
        'starred': starred,
      };

  factory DataSet.fromJson(Map<String, dynamic> json) => DataSet(
        id: json['id'] as String,
        containerId: json['containerId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        startTime: DateTime.parse(json['startTime'] as String),
        notes: json['notes'] as String? ?? '',
        starred: json['starred'] as bool? ?? false,
      );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'dataSetId': dataSetId,
        'tSeconds': tSeconds,
        'value': value,
      };

  factory DataPoint.fromJson(Map<String, dynamic> json) => DataPoint(
        id: json['id'] as String,
        dataSetId: json['dataSetId'] as String,
        tSeconds: (json['tSeconds'] as num).toDouble(),
        value: json['value'] as int,
      );
}
