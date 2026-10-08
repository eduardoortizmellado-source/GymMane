import 'dart:math' as math;

import '../models/calorie_estimate.dart';

class CalorieInputs {
  const CalorieInputs({
    required this.weightKg,
    required this.durationSeconds,
    required this.activeSeconds,
    this.bmrKcalPerDay,
    this.watchTotalKcal,
    this.averageHeartRate,
    this.heartRateCoverage = 0,
    this.motionCoverage = 0,
    this.motionIntensity = 0.5,
    this.volumeKg = 0,
  });

  final double weightKg;
  final int durationSeconds;
  final int activeSeconds;
  final double? bmrKcalPerDay;
  final double? watchTotalKcal;
  final double? averageHeartRate;
  final double heartRateCoverage;
  final double motionCoverage;
  final double motionIntensity;
  final double volumeKg;
}

class CalorieEngine {
  const CalorieEngine();

  static const version = 'gymmane-cal-v1';

  CalorieEstimate estimate(CalorieInputs input) {
    if (input.weightKg <= 0 || input.durationSeconds <= 0) {
      return const CalorieEstimate(
        activeKcal: 0,
        lowKcal: 0,
        highKcal: 0,
        confidence: 0,
        version: version,
        sources: ['insufficient_data'],
      );
    }

    final durationMinutes = input.durationSeconds / 60;
    final workRatio = (input.activeSeconds / input.durationSeconds).clamp(0.0, 1.0);
    final movement = input.motionIntensity.clamp(0.0, 1.0);
    final met = 3.5 + 2.5 * (0.65 * workRatio + 0.35 * movement);
    final metGross = met * 3.5 * input.weightKg / 200 * durationMinutes;
    final fallbackBmr = 22.0 * input.weightKg;
    final bmr = input.bmrKcalPerDay ?? fallbackBmr;
    final basalDuringSession = bmr * input.durationSeconds / 86400;
    final metActive = math.max(0.0, metGross - basalDuringSession);

    final watchTotal = input.watchTotalKcal;
    final watchActive = watchTotal == null ? null : math.max(0.0, watchTotal - basalDuringSession);
    final hrCoverage = input.heartRateCoverage.clamp(0.0, 1.0);
    final motionCoverage = input.motionCoverage.clamp(0.0, 1.0);
    final sensorCoverage = (hrCoverage * 0.7 + motionCoverage * 0.3).clamp(0.0, 1.0);

    final active = watchActive == null
        ? metActive
        : watchActive * (0.45 + 0.25 * sensorCoverage) + metActive * (0.55 - 0.25 * sensorCoverage);
    final confidence = watchActive == null
        ? (0.25 + 0.2 * motionCoverage).clamp(0.0, 0.5)
        : (0.4 + 0.35 * sensorCoverage).clamp(0.0, 0.8);
    final uncertainty = 0.55 - confidence * 0.35;

    return CalorieEstimate(
      activeKcal: active,
      lowKcal: math.max(0.0, active * (1 - uncertainty)),
      highKcal: active * (1 + uncertainty),
      confidence: confidence,
      version: version,
      sources: [
        'met_strength_training',
        if (watchActive != null) 'watch_total_minus_basal',
        if (input.averageHeartRate != null && hrCoverage > 0) 'heart_rate',
        if (motionCoverage > 0) 'motion',
      ],
      watchTotalKcal: watchTotal,
      estimatedBasalKcal: basalDuringSession,
    );
  }
}
