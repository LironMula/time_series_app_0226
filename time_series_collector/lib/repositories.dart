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
    return _containers.firstWhere(
      (c) => c.id == id,
      orElse: () => DataContainer(name: 'Unknown'),
    );
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
}
