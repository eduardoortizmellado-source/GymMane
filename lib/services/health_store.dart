import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/body_composition.dart';
import '../models/telemetry.dart';
import 'calorie_engine.dart';

class HealthStore {
  HealthStore._();
  static final instance = HealthStore._();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'gymmane_health_v1.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE body_composition(
            id TEXT PRIMARY KEY,
            measured_at INTEGER NOT NULL,
            source TEXT NOT NULL,
            fingerprint TEXT UNIQUE,
            health_connect_id TEXT,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE telemetry_session(
            id TEXT PRIMARY KEY,
            started_at INTEGER NOT NULL,
            ended_at INTEGER,
            status TEXT NOT NULL DEFAULT 'recording',
            watch_calories REAL,
            algorithm_version TEXT,
            estimate_low REAL,
            estimate_mid REAL,
            estimate_high REAL,
            confidence REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE sensor_sample(
            session_id TEXT NOT NULL,
            at INTEGER NOT NULL,
            heart_rate REAL,
            heart_accuracy INTEGER,
            calories_total REAL,
            accel_rms REAL,
            accel_variance REAL,
            gyro_rms REAL,
            PRIMARY KEY(session_id, at),
            FOREIGN KEY(session_id) REFERENCES telemetry_session(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE workout_phase(
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER,
            exercise_id TEXT,
            set_id TEXT,
            FOREIGN KEY(session_id) REFERENCES telemetry_session(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX sample_session_time ON sensor_sample(session_id, at)');
        await db.execute('CREATE INDEX composition_time ON body_composition(measured_at)');
      },
    );
  }

  Database get db {
    final value = _db;
    if (value == null) throw StateError('HealthStore.init() has not completed');
    return value;
  }

  Future<Uint8List?> exportBytes() async {
    final database = _db;
    if (database == null) return null;
    await database.execute('PRAGMA wal_checkpoint(FULL)');
    final file = File(database.path);
    return file.existsSync() ? file.readAsBytes() : null;
  }

  Future<void> restoreBytes(Uint8List bytes) async {
    final database = _db;
    final root = await getDatabasesPath();
    final path = database?.path ?? p.join(root, 'gymmane_health_v1.db');
    if (database != null) await database.close();
    _db = null;
    await File(path).writeAsBytes(bytes, flush: true);
    await init();
  }

  Future<bool> saveComposition(BodyCompositionEntry entry) async {
    try {
      await db.insert('body_composition', {
        'id': entry.id,
        'measured_at': entry.measuredAt.millisecondsSinceEpoch,
        'source': entry.source,
        'fingerprint': entry.sourceFingerprint,
        'health_connect_id': entry.healthConnectId,
        'payload': jsonEncode(entry.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return true;
    } on DatabaseException {
      return false;
    }
  }

  Future<List<BodyCompositionEntry>> compositions() async {
    final rows = await db.query('body_composition', orderBy: 'measured_at DESC');
    return rows
        .map((row) => BodyCompositionEntry.fromJson(
            (jsonDecode(row['payload'] as String) as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> startTelemetry(String id, DateTime at) async {
    final database = _db;
    if (database == null) return;
    await database.insert(
      'telemetry_session',
      {'id': id, 'started_at': at.millisecondsSinceEpoch, 'status': 'recording'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> finishTelemetry(
    String id,
    DateTime at, {
    required double weightKg,
    double? bmrKcalPerDay,
    double? watchCalories,
  }) async {
    final database = _db;
    if (database == null) return;
    final aggregates = await database.rawQuery('''
      SELECT COUNT(*) AS samples,
             AVG(heart_rate) AS average_hr,
             COUNT(heart_rate) AS hr_samples,
             MAX(calories_total) AS watch_calories,
             AVG(accel_variance) AS motion
      FROM sensor_sample WHERE session_id = ?
    ''', [id]);
    final phaseRows = await database.rawQuery('''
      SELECT COALESCE(SUM(ended_at - started_at), 0) AS active_ms
      FROM workout_phase WHERE session_id = ? AND kind = 'set'
    ''', [id]);
    final row = aggregates.single;
    final totalSamples = (row['samples'] as num?)?.toInt() ?? 0;
    final hrSamples = (row['hr_samples'] as num?)?.toInt() ?? 0;
    final startedRows = await database.query(
      'telemetry_session',
      columns: ['started_at'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final startedAt = startedRows.isEmpty
        ? at
        : DateTime.fromMillisecondsSinceEpoch(startedRows.single['started_at'] as int);
    final durationSeconds = at.difference(startedAt).inSeconds.clamp(0, 24 * 60 * 60);
    final activeSeconds = (((phaseRows.single['active_ms'] as num?)?.toDouble() ?? 0) / 1000).round();
    final storedWatchCalories = watchCalories ?? (row['watch_calories'] as num?)?.toDouble();
    final estimate = const CalorieEngine().estimate(CalorieInputs(
      weightKg: weightKg,
      durationSeconds: durationSeconds,
      activeSeconds: activeSeconds,
      watchTotalKcal: storedWatchCalories,
      bmrKcalPerDay: bmrKcalPerDay,
      averageHeartRate: (row['average_hr'] as num?)?.toDouble(),
      heartRateCoverage: totalSamples == 0 ? 0 : hrSamples / totalSamples,
      motionCoverage: totalSamples == 0 ? 0 : 1,
      motionIntensity: (((row['motion'] as num?)?.toDouble() ?? 0) / 6).clamp(0, 1),
    ));
    await database.update(
      'telemetry_session',
      {
        'ended_at': at.millisecondsSinceEpoch,
        'status': 'complete',
        'watch_calories': storedWatchCalories,
        'algorithm_version': estimate.version,
        'estimate_low': estimate.lowKcal,
        'estimate_mid': estimate.activeKcal,
        'estimate_high': estimate.highKcal,
        'confidence': estimate.confidence,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveSamples(String sessionId, Iterable<SensorSample> samples) async {
    final database = _db;
    if (database == null) return;
    final batch = database.batch();
    for (final s in samples) {
      batch.insert(
        'sensor_sample',
        {
          'session_id': sessionId,
          'at': s.at.millisecondsSinceEpoch,
          'heart_rate': s.heartRate,
          'heart_accuracy': s.heartRateAccuracy,
          'calories_total': s.totalCalories,
          'accel_rms': s.accelRms,
          'accel_variance': s.accelVariance,
          'gyro_rms': s.gyroRms,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> savePhase(WorkoutPhase phase) async {
    final database = _db;
    if (database == null) return;
    await database.insert(
      'workout_phase',
      {
        'id': phase.id,
        'session_id': phase.sessionId,
        'kind': phase.kind.name,
        'started_at': phase.startedAt.millisecondsSinceEpoch,
        'ended_at': phase.endedAt?.millisecondsSinceEpoch,
        'exercise_id': phase.exerciseId,
        'set_id': phase.setId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
