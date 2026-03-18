import 'dart:convert';

import 'models.dart';

class ContainerRepository {
  final List<DataContainer> _containers = [];

  List<DataContainer> getAll() => List.unmodifiable(_containers);

  void add(DataContainer container) {
    _containers.add(container);
  }

  void update(DataContainer container) {
    final index = _containers.indexWhere((c) => c.id == container.id);
    if (index != -1) {
      _containers[index] = container;
    }
  }

  void remove(String id) {
    _containers.removeWhere((c) => c.id == id);
  }

  DataContainer? getById(String id) {
    final index = _containers.indexWhere((c) => c.id == id);
    return index == -1 ? null : _containers[index];
  }

  void replaceAll(List<DataContainer> containers) {
    _containers
      ..clear()
      ..addAll(containers);
  }
}

class DataSetRepository {
  final List<DataSet> _sets = [];
  final List<DataPoint> _points = [];

  List<DataSet> getByContainer(String containerId) =>
      _sets.where((s) => s.containerId == containerId).toList();

  List<DataPoint> getPoints(String dataSetId) =>
      _points.where((p) => p.dataSetId == dataSetId).toList()
        ..sort((a, b) => a.tSeconds.compareTo(b.tSeconds));

  void addSet(DataSet set) {
    _sets.add(set);
  }

  void addPoint(DataPoint p) {
    _points.add(p);
  }

  void updateSet(DataSet set) {
    final i = _sets.indexWhere((s) => s.id == set.id);
    if (i != -1) _sets[i] = set;
  }

  void toggleSetStarred(String setId) {
    final i = _sets.indexWhere((s) => s.id == setId);
    if (i == -1) return;
    _sets[i] = _sets[i].copyWith(starred: !_sets[i].starred);
  }

  void removeByContainer(String containerId) {
    final setIds = _sets
        .where((s) => s.containerId == containerId)
        .map((s) => s.id)
        .toSet();
    _sets.removeWhere((s) => s.containerId == containerId);
    _points.removeWhere((p) => setIds.contains(p.dataSetId));
  }

  String exportContainerPayload(DataContainer container) {
    final sets = getByContainer(container.id);
    final setIds = sets.map((s) => s.id).toSet();
    final points = _points.where((p) => setIds.contains(p.dataSetId)).toList();

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
      _sets.add(newSet);
    }

    for (final point in imported.points) {
      final mappedId = setIdMap[point.dataSetId];
      if (mappedId == null) continue;
      _points.add(
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
