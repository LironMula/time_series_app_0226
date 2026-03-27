import 'dart:convert';

import 'database.dart';
import 'models.dart';

class ContainerRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  late List<DataContainer> _containerCache;

  ContainerRepository({List<DataContainer>? initialContainers}) {
    _containerCache = initialContainers ?? [];
  }

  // Initialize from database (should be called during app startup)
  Future<void> initialize() async {
    _containerCache = await _db.getAllContainers();
  }

  // Synchronous access to cached data
  List<DataContainer> getAll() => List.unmodifiable(_containerCache);

  void add(DataContainer container) {
    _containerCache.add(container);
    // Persist to database asynchronously
    _db.insertContainer(container).ignore();
  }

  void update(DataContainer container) {
    final index = _containerCache.indexWhere((c) => c.id == container.id);
    if (index != -1) {
      _containerCache[index] = container;
    }
    // Persist to database asynchronously
    _db.updateContainer(container).ignore();
  }

  void remove(String id) {
    _containerCache.removeWhere((c) => c.id == id);
    // Persist to database asynchronously
    _db.deleteContainer(id).ignore();
  }

  DataContainer? getById(String id) {
    final index = _containerCache.indexWhere((c) => c.id == id);
    return index == -1 ? null : _containerCache[index];
  }

  void replaceAll(List<DataContainer> containers) {
    _containerCache
      ..clear()
      ..addAll(containers);
    // Persist asynchronously with a batch operation
    _replaceAllInDb(containers).ignore();
  }

  Future<void> _replaceAllInDb(List<DataContainer> containers) async {
    final existing = await _db.getAllContainers();
    for (final c in existing) {
      await _db.deleteContainer(c.id);
    }
    for (final c in containers) {
      await _db.insertContainer(c);
    }
  }
}

class DataSetRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  late List<DataSet> _setCache;
  late List<DataPoint> _pointCache;

  DataSetRepository({List<DataSet>? initialSets, List<DataPoint>? initialPoints}) {
    _setCache = initialSets ?? [];
    _pointCache = initialPoints ?? [];
  }

  // Initialize from database (should be called during app startup)
  Future<void> initialize() async {
    // Load all datasets and datapoints from DB
    _setCache = await _db.getAllDataSets();
    _pointCache = await _db.getAllDataPoints();
  }

  List<DataSet> getByContainer(String containerId) =>
      _setCache.where((s) => s.containerId == containerId).toList();

  List<DataPoint> getPoints(String dataSetId) =>
      _pointCache.where((p) => p.dataSetId == dataSetId).toList()
        ..sort((a, b) => a.tSeconds.compareTo(b.tSeconds));

  void addSet(DataSet set) {
    _setCache.add(set);
    // Persist asynchronously
    _db.insertDataSet(set).ignore();
  }

  void addPoint(DataPoint p) {
    _pointCache.add(p);
    // Persist asynchronously
    _db.insertDataPoint(p).ignore();
  }

  void updateSet(DataSet set) {
    final i = _setCache.indexWhere((s) => s.id == set.id);
    if (i != -1) _setCache[i] = set;
    // Persist asynchronously
    _db.updateDataSet(set).ignore();
  }

  void toggleSetStarred(String setId) {
    final i = _setCache.indexWhere((s) => s.id == setId);
    if (i == -1) return;
    _setCache[i] = _setCache[i].copyWith(starred: !_setCache[i].starred);
    // Persist asynchronously
    _db.updateDataSet(_setCache[i]).ignore();
  }

  void removeByContainer(String containerId) {
    final setIds = _setCache
        .where((s) => s.containerId == containerId)
        .map((s) => s.id)
        .toSet();
    _setCache.removeWhere((s) => s.containerId == containerId);
    _pointCache.removeWhere((p) => setIds.contains(p.dataSetId));
    // Persist asynchronously
    _db.deleteDataSetsByContainer(containerId).ignore();
  }

  String exportContainerPayload(DataContainer container) {
    final sets = getByContainer(container.id);
    final setIds = sets.map((s) => s.id).toSet();
    final points = _pointCache.where((p) => setIds.contains(p.dataSetId)).toList();

    return const JsonEncoder.withIndent('  ').convert({
      'container': container.toJson(),
      'sets': sets.map((s) => s.toJson()).toList(),
      'points': points.map((p) => p.toJson()).toList(),
    });
  }

  ImportedContainerData importContainerPayload(String jsonText) {
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    final container = DataContainer.fromJson(
      (decoded['container'] as Map).cast<String, dynamic>(),
    );
    final sets = ((decoded['sets'] as List?) ?? const [])
        .map((e) => DataSet.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final points = ((decoded['points'] as List?) ?? const [])
        .map((e) => DataPoint.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return ImportedContainerData(container: container, sets: sets, points: points);
  }

  void mergeImported(ImportedContainerData imported, {required String newContainerId}) {
    final setIdMap = <String, String>{};
    for (final set in imported.sets) {
      final newSet = DataSet(
        containerId: newContainerId,
        createdAt: set.createdAt,
        startTime: set.startTime,
        notes: set.notes,
        starred: set.starred,
      );
      setIdMap[set.id] = newSet.id;
      addSet(newSet);
    }

    for (final point in imported.points) {
      final mappedId = setIdMap[point.dataSetId];
      if (mappedId == null) continue;
      addPoint(
        DataPoint(
          dataSetId: mappedId,
          tSeconds: point.tSeconds,
          value: point.value,
        ),
      );
    }
  }
}

class ImportedContainerData {
  final DataContainer container;
  final List<DataSet> sets;
  final List<DataPoint> points;

  ImportedContainerData({
    required this.container,
    required this.sets,
    required this.points,
  });
}
