class ExerciseHistoryMetrics {
  const ExerciseHistoryMetrics({
    required this.activeSeconds,
    required this.restSeconds,
    this.averageHeartRate,
    this.maxHeartRate,
    this.estimatedKcal,
    this.sensorCoverage = 0,
  });

  final int activeSeconds;
  final int restSeconds;
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? estimatedKcal;
  final double sensorCoverage;
}

class SessionHistoryMetrics {
  const SessionHistoryMetrics({
    required this.activeSeconds,
    required this.restSeconds,
    required this.exercises,
    this.averageHeartRate,
    this.maxHeartRate,
    this.estimatedKcal,
    this.estimateLow,
    this.estimateHigh,
    this.estimateConfidence,
    this.sensorCoverage = 0,
  });

  final int activeSeconds;
  final int restSeconds;
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? estimatedKcal;
  final double? estimateLow;
  final double? estimateHigh;
  final double? estimateConfidence;
  final double sensorCoverage;
  final Map<String, ExerciseHistoryMetrics> exercises;
}
