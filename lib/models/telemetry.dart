class SensorSample {
  const SensorSample({
    required this.at,
    this.heartRate,
    this.heartRateAccuracy,
    this.totalCalories,
    this.accelRms,
    this.accelVariance,
    this.gyroRms,
  });

  final DateTime at;
  final double? heartRate;
  final int? heartRateAccuracy;
  final double? totalCalories;
  final double? accelRms;
  final double? accelVariance;
  final double? gyroRms;
}

enum WorkoutPhaseKind { set, rest, paused }

class WorkoutPhase {
  const WorkoutPhase({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.startedAt,
    this.endedAt,
    this.exerciseId,
    this.setId,
  });

  final String id;
  final String sessionId;
  final WorkoutPhaseKind kind;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? exerciseId;
  final String? setId;
}
