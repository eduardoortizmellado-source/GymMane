import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/services/calorie_engine.dart';

void main() {
  const engine = CalorieEngine();

  test('the estimate is deterministic and exposes a range', () {
    const input = CalorieInputs(
      weightKg: 75.4,
      durationSeconds: 3600,
      activeSeconds: 1500,
      bmrKcalPerDay: 1622,
      watchTotalKcal: 420,
      averageHeartRate: 128,
      heartRateCoverage: 0.92,
      motionCoverage: 0.95,
      motionIntensity: 0.6,
      volumeKg: 8500,
    );
    final first = engine.estimate(input);
    final second = engine.estimate(input);

    expect(first.toJson(), second.toJson());
    expect(first.lowKcal, lessThan(first.activeKcal));
    expect(first.highKcal, greaterThan(first.activeKcal));
    expect(first.watchTotalKcal, 420);
    expect(first.estimatedBasalKcal, closeTo(67.58, 0.1));
    expect(first.confidence, inInclusiveRange(0, 0.8));
  });

  test('MET fallback works without the watch and is less confident', () {
    final fallback = engine.estimate(const CalorieInputs(
      weightKg: 75,
      durationSeconds: 3600,
      activeSeconds: 1200,
    ));
    final watch = engine.estimate(const CalorieInputs(
      weightKg: 75,
      durationSeconds: 3600,
      activeSeconds: 1200,
      watchTotalKcal: 350,
      heartRateCoverage: 1,
      motionCoverage: 1,
    ));

    expect(fallback.activeKcal, greaterThan(0));
    expect(fallback.confidence, lessThan(watch.confidence));
    expect(fallback.sources, contains('met_strength_training'));
  });

  test('invalid inputs never produce negative or invented calories', () {
    final estimate = engine.estimate(const CalorieInputs(
      weightKg: 0,
      durationSeconds: 0,
      activeSeconds: 0,
    ));
    expect(estimate.activeKcal, 0);
    expect(estimate.confidence, 0);
  });
}
