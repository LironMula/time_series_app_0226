import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path_util;

import 'models.dart';

// Import sqlite_common_ffi for non-web platforms
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Current database schema version - increment when schema changes
const int CURRENT_DB_VERSION = 1;

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  static DatabaseHelper get instance => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initializeDatabase();
    return _database!;
  }

  Future<Database> _initializeDatabase() async {
    String dbPath;

    if (kIsWeb) {
      // For web, sqflite uses IndexedDB automatically
      // Just use a simple database name
      dbPath = 'time_series_collector';
    } else {
      // For mobile/desktop, use file system path
      final documentsDirectory = await getApplicationDocumentsDirectory();
      dbPath = path_util.join(documentsDirectory.path, 'time_series_collector.db');
    }

    return openDatabase(
      dbPath,
      version: CURRENT_DB_VERSION,
      onCreate: _createTables,
      onOpen: _onDatabaseOpen,
    );
  }

  Future<void> _onDatabaseOpen(Database db) async {
    // Check and validate database version
    final versionCheck = await _checkDatabaseVersion(db);
    if (!versionCheck.isCompatible) {
      throw DatabaseVersionMismatchException(
        storedVersion: versionCheck.storedVersion,
        currentVersion: CURRENT_DB_VERSION,
      );
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Create metadata table for version tracking
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Store the current database version
    await db.insert('_metadata', {
      'key': 'db_version',
      'value': CURRENT_DB_VERSION.toString(),
    });

    // Create containers table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS containers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        settings TEXT NOT NULL
      )
    ''');

    // Create datasets table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS datasets (
        id TEXT PRIMARY KEY,
        containerId TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        startTime TEXT NOT NULL,
        notes TEXT NOT NULL,
        starred INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(containerId) REFERENCES containers(id) ON DELETE CASCADE
      )
    ''');

    // Create datapoints table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS datapoints (
        id TEXT PRIMARY KEY,
        datasetId TEXT NOT NULL,
        tSeconds REAL NOT NULL,
        value INTEGER NOT NULL,
        FOREIGN KEY(datasetId) REFERENCES datasets(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<_VersionCheck> _checkDatabaseVersion(Database db) async {
    try {
      final result = await db.query(
        '_metadata',
        where: 'key = ?',
        whereArgs: ['db_version'],
      );

      if (result.isEmpty) {
        // No version found, assume this is a legacy database or fresh install
        return _VersionCheck(storedVersion: 0, currentVersion: CURRENT_DB_VERSION);
      }

      final storedVersion = int.parse(result.first['value'] as String);
      return _VersionCheck(
        storedVersion: storedVersion,
        currentVersion: CURRENT_DB_VERSION,
      );
    } catch (e) {
      // Error reading version, treat as incompatible
      return _VersionCheck(storedVersion: 0, currentVersion: CURRENT_DB_VERSION);
    }
  }

  // Call this after user chooses to erase data
  Future<void> eraseAllData() async {
    final db = await database;
    await db.delete('datapoints');
    await db.delete('datasets');
    await db.delete('containers');
    // Update version
    await db.update(
      '_metadata',
      {'value': CURRENT_DB_VERSION.toString()},
      where: 'key = ?',
      whereArgs: ['db_version'],
    );
  }

  // Container operations
  Future<void> insertContainer(DataContainer container) async {
    final db = await database;
    await db.insert('containers', {
      'id': container.id,
      'name': container.name,
      'createdAt': container.createdAt.toIso8601String(),
      'settings': jsonEncode(container.settings.toJson()),
    });
  }

  Future<void> updateContainer(DataContainer container) async {
    final db = await database;
    await db.update(
      'containers',
      {
        'name': container.name,
        'settings': jsonEncode(container.settings.toJson()),
      },
      where: 'id = ?',
      whereArgs: [container.id],
    );
  }

  Future<void> deleteContainer(String id) async {
    final db = await database;
    await db.delete('containers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DataContainer>> getAllContainers() async {
    final db = await database;
    final maps = await db.query('containers');
    return maps
        .map((map) => DataContainer(
              id: map['id'] as String,
              name: map['name'] as String,
              createdAt: DateTime.parse(map['createdAt'] as String),
              settings: ContainerSettings.fromJson(
                jsonDecode(map['settings'] as String) as Map<String, dynamic>,
              ),
            ))
        .toList();
  }

  Future<DataContainer?> getContainerById(String id) async {
    final db = await database;
    final maps = await db.query('containers', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final map = maps.first;
    return DataContainer(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      settings: ContainerSettings.fromJson(
        jsonDecode(map['settings'] as String) as Map<String, dynamic>,
      ),
    );
  }

  // Dataset operations
  Future<void> insertDataSet(DataSet dataSet) async {
    final db = await database;
    await db.insert('datasets', {
      'id': dataSet.id,
      'containerId': dataSet.containerId,
      'createdAt': dataSet.createdAt.toIso8601String(),
      'startTime': dataSet.startTime.toIso8601String(),
      'notes': dataSet.notes,
      'starred': dataSet.starred ? 1 : 0,
    });
  }

  Future<void> updateDataSet(DataSet dataSet) async {
    final db = await database;
    await db.update(
      'datasets',
      {
        'notes': dataSet.notes,
        'starred': dataSet.starred ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [dataSet.id],
    );
  }

  Future<void> deleteDataSet(String id) async {
    final db = await database;
    await db.delete('datasets', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DataSet>> getDataSetsByContainer(String containerId) async {
    final db = await database;
    final maps = await db.query(
      'datasets',
      where: 'containerId = ?',
      whereArgs: [containerId],
    );
    return maps
        .map((map) => DataSet(
              id: map['id'] as String,
              containerId: map['containerId'] as String,
              createdAt: DateTime.parse(map['createdAt'] as String),
              startTime: DateTime.parse(map['startTime'] as String),
              notes: map['notes'] as String? ?? '',
              starred: (map['starred'] as int?) == 1,
            ))
        .toList();
  }

  Future<List<DataSet>> getAllDataSets() async {
    final db = await database;
    final maps = await db.query('datasets');
    return maps
        .map((map) => DataSet(
              id: map['id'] as String,
              containerId: map['containerId'] as String,
              createdAt: DateTime.parse(map['createdAt'] as String),
              startTime: DateTime.parse(map['startTime'] as String),
              notes: map['notes'] as String? ?? '',
              starred: (map['starred'] as int?) == 1,
            ))
        .toList();
  }

  Future<List<DataPoint>> getAllDataPoints() async {
    final db = await database;
    final maps = await db.query('datapoints', orderBy: 'tSeconds ASC');
    return maps
        .map((map) => DataPoint(
              id: map['id'] as String,
              dataSetId: map['datasetId'] as String,
              tSeconds: (map['tSeconds'] as num).toDouble(),
              value: map['value'] as int,
            ))
        .toList();
  }

  Future<void> deleteDataSetsByContainer(String containerId) async {
    final db = await database;
    await db.delete('datasets', where: 'containerId = ?', whereArgs: [containerId]);
  }

  // DataPoint operations
  Future<void> insertDataPoint(DataPoint dataPoint) async {
    final db = await database;
    await db.insert('datapoints', {
      'id': dataPoint.id,
      'datasetId': dataPoint.dataSetId,
      'tSeconds': dataPoint.tSeconds,
      'value': dataPoint.value,
    });
  }

  Future<List<DataPoint>> getDataPointsByDataSet(String dataSetId) async {
    final db = await database;
    final maps = await db.query(
      'datapoints',
      where: 'datasetId = ?',
      whereArgs: [dataSetId],
      orderBy: 'tSeconds ASC',
    );
    return maps
        .map((map) => DataPoint(
              id: map['id'] as String,
              dataSetId: map['datasetId'] as String,
              tSeconds: (map['tSeconds'] as num).toDouble(),
              value: map['value'] as int,
            ))
        .toList();
  }

  Future<void> deleteDataPointsByDataSet(String dataSetId) async {
    final db = await database;
    await db.delete('datapoints', where: 'datasetId = ?', whereArgs: [dataSetId]);
  }

  // Utility methods
  Future<bool> isEmpty() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM containers');
    return (result.first['count'] as int?) == 0;
  }
}

// Exception for database version mismatch
class DatabaseVersionMismatchException implements Exception {
  final int storedVersion;
  final int currentVersion;

  DatabaseVersionMismatchException({
    required this.storedVersion,
    required this.currentVersion,
  });

  @override
  String toString() {
    if (storedVersion == 0) {
      return 'Database not initialized or corrupted';
    }
    if (storedVersion > currentVersion) {
      return 'Database version $storedVersion is newer than app version $currentVersion. '
          'Application needs to be upgraded.';
    }
    return 'Database version $storedVersion is incompatible with app version $currentVersion. '
        'Data format has changed.';
  }
}

class _VersionCheck {
  final int storedVersion;
  final int currentVersion;

  _VersionCheck({required this.storedVersion, required this.currentVersion});

  bool get isCompatible => storedVersion == currentVersion;
  bool get isNewer => storedVersion > currentVersion;
  bool get isOlder => storedVersion < currentVersion && storedVersion > 0;
}

