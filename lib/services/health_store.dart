import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/body_composition.dart';
import '../models/calorie_estimate.dart';
import '../models/history_metrics.dart';
import '../models/telemetry.dart';
import '../models/workout.dart';
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
        .map(
          (row) => BodyCompositionEntry.fromJson(
            (jsonDecode(row['payload'] as String) as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
  }

  Future<CalorieEstimate?> calorieEstimateForSession(String? sessionId) async {
    if (sessionId == null || sessionId.isEmpty) return null;
    final database = _db;
    if (database == null) return null;
    final rows = await database.query(
      'telemetry_session',
      columns: [
        'watch_calories',
        'algorithm_version',
        'estimate_low',
        'estimate_mid',
        'estimate_high',
        'confidence',
      ],
      where: 'id = ? AND status = ?',
      whereArgs: [sessionId, 'complete'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final mid = (row['estimate_mid'] as num?)?.toDouble();
    final low = (row['estimate_low'] as num?)?.toDouble();
    final high = (row['estimate_high'] as num?)?.toDouble();
    final confidence = (row['confidence'] as num?)?.toDouble();
    if (mid == null || low == null || high == null || confidence == null) return null;
    return CalorieEstimate(
      activeKcal: mid,
      lowKcal: low,
      highKcal: high,
      confidence: confidence,
      version: row['algorithm_version'] as String? ?? CalorieEngine.version,
      sources: const [],
      watchTotalKcal: (row['watch_calories'] as num?)?.toDouble(),
    );
  }

  Future<SessionHistoryMetrics> historyMetricsForSession(LoggedSession session) async {
    final sessionId = session.telemetryId;
    final database = _db;
    Map<String, Object?>? telemetry;
    var samples = <Map<String, Object?>>[];
    var phases = <Map<String, Object?>>[];
    if (database != null && sessionId != null && sessionId.isNotEmpty) {
      final rows = await database.query(
        'telemetry_session',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (rows.isNotEmpty) telemetry = rows.single;
      samples = await database.query(
        'sensor_sample',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'at ASC',
      );
      phases = await database.query(
        'workout_phase',
        where: "session_id = ? AND kind = 'set' AND ended_at IS NOT NULL",
        whereArgs: [sessionId],
        orderBy: 'started_at ASC',
      );
    }

    final intervals = <String, List<(int, int)>>{};
    for (final phase in phases) {
      final exerciseId = phase['exercise_id'] as String?;
      final start = (phase['started_at'] as num?)?.toInt();
      final end = (phase['ended_at'] as num?)?.toInt();
      if (exerciseId == null || start == null || end == null || end < start) continue;
      intervals.putIfAbsent(exerciseId, () => []).add((start, end));
    }
    for (final exercise in session.exercises) {
      if ((intervals[exercise.id] ?? const []).isNotEmpty) continue;
      for (final set in exercise.sets) {
        final start = set.startedAt?.millisecondsSinceEpoch;
        final end = set.completedAt?.millisecondsSinceEpoch;
        if (start == null || end == null || end < start) continue;
        intervals.putIfAbsent(exercise.id, () => []).add((start, end));
      }
    }

    final totalActiveMs = intervals.values
        .expand((items) => items)
        .fold<int>(0, (sum, item) => sum + item.$2 - item.$1);
    final estimateMid = (telemetry?['estimate_mid'] as num?)?.toDouble();
    final allHeartRates = samples
        .map((sample) => (sample['heart_rate'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final exerciseMetrics = <String, ExerciseHistoryMetrics>{};
    for (final exercise in session.exercises) {
      final spans = [...(intervals[exercise.id] ?? const <(int, int)>[])]
        ..sort((a, b) => a.$1.compareTo(b.$1));
      final activeMs = spans.fold<int>(0, (sum, item) => sum + item.$2 - item.$1);
      var restMs = 0;
      for (var i = 1; i < spans.length; i++) {
        restMs += (spans[i].$1 - spans[i - 1].$2).clamp(0, 15 * 60 * 1000);
      }
      final hrs = <double>[];
      for (final sample in samples) {
        final at = (sample['at'] as num?)?.toInt();
        final hr = (sample['heart_rate'] as num?)?.toDouble();
        if (at == null || hr == null) continue;
        if (spans.any((span) => at >= span.$1 && at <= span.$2)) hrs.add(hr);
      }
      final workingSets = exercise.workingSets.length;
      final totalSets = session.setCount;
      final share = totalActiveMs > 0
          ? activeMs / totalActiveMs
          : totalSets > 0
          ? workingSets / totalSets
          : 0.0;
      exerciseMetrics[exercise.id] = ExerciseHistoryMetrics(
        activeSeconds: (activeMs / 1000).round(),
        restSeconds: (restMs / 1000).round(),
        averageHeartRate: hrs.isEmpty ? null : hrs.reduce((a, b) => a + b) / hrs.length,
        maxHeartRate: hrs.isEmpty ? null : hrs.reduce((a, b) => a > b ? a : b),
        estimatedKcal: estimateMid == null ? null : estimateMid * share,
        sensorCoverage: activeMs <= 0 ? 0 : (hrs.length / (activeMs / 1000)).clamp(0, 1),
      );
    }

    final activeSeconds = (totalActiveMs / 1000).round();
    return SessionHistoryMetrics(
      activeSeconds: activeSeconds,
      restSeconds: (session.durationSec - activeSeconds).clamp(0, session.durationSec),
      averageHeartRate: allHeartRates.isEmpty
          ? null
          : allHeartRates.reduce((a, b) => a + b) / allHeartRates.length,
      maxHeartRate: allHeartRates.isEmpty ? null : allHeartRates.reduce((a, b) => a > b ? a : b),
      estimatedKcal: estimateMid,
      estimateLow: (telemetry?['estimate_low'] as num?)?.toDouble(),
      estimateHigh: (telemetry?['estimate_high'] as num?)?.toDouble(),
      estimateConfidence: (telemetry?['confidence'] as num?)?.toDouble(),
      sensorCoverage: session.durationSec <= 0 ? 0 : (allHeartRates.length / session.durationSec).clamp(0, 1),
      exercises: exerciseMetrics,
    );
  }

  Future<void> startTelemetry(String id, DateTime at) async {
    final database = _db;
    if (database == null) return;
    await database.insert('telemetry_session', {
      'id': id,
      'started_at': at.millisecondsSinceEpoch,
      'status': 'recording',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
    final aggregates = await database.rawQuery(
      '''
      SELECT COUNT(*) AS samples,
             AVG(heart_rate) AS average_hr,
             COUNT(heart_rate) AS hr_samples,
             MAX(calories_total) AS watch_calories,
             AVG(accel_variance) AS motion
      FROM sensor_sample WHERE session_id = ?
    ''',
      [id],
    );
    final phaseRows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(ended_at - started_at), 0) AS active_ms
      FROM workout_phase WHERE session_id = ? AND kind = 'set'
    ''',
      [id],
    );
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
    final estimate = const CalorieEngine().estimate(
      CalorieInputs(
        weightKg: weightKg,
        durationSeconds: durationSeconds,
        activeSeconds: activeSeconds,
        watchTotalKcal: storedWatchCalories,
        bmrKcalPerDay: bmrKcalPerDay,
        averageHeartRate: (row['average_hr'] as num?)?.toDouble(),
        heartRateCoverage: totalSamples == 0 ? 0 : hrSamples / totalSamples,
        motionCoverage: totalSamples == 0 ? 0 : 1,
        motionIntensity: (((row['motion'] as num?)?.toDouble() ?? 0) / 6).clamp(0, 1),
      ),
    );
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
      batch.insert('sensor_sample', {
        'session_id': sessionId,
        'at': s.at.millisecondsSinceEpoch,
        'heart_rate': s.heartRate,
        'heart_accuracy': s.heartRateAccuracy,
        'calories_total': s.totalCalories,
        'accel_rms': s.accelRms,
        'accel_variance': s.accelVariance,
        'gyro_rms': s.gyroRms,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> savePhase(WorkoutPhase phase) async {
    final database = _db;
    if (database == null) return;
    await database.insert('workout_phase', {
      'id': phase.id,
      'session_id': phase.sessionId,
      'kind': phase.kind.name,
      'started_at': phase.startedAt.millisecondsSinceEpoch,
      'ended_at': phase.endedAt?.millisecondsSinceEpoch,
      'exercise_id': phase.exerciseId,
      'set_id': phase.setId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePhaseForSet(String sessionId, String setId) async {
    final database = _db;
    if (database == null) return;
    await database.delete(
      'workout_phase',
      where: 'session_id = ? AND set_id = ?',
      whereArgs: [sessionId, setId],
    );
  }
}
