class CalorieEstimate {
  const CalorieEstimate({
    required this.activeKcal,
    required this.lowKcal,
    required this.highKcal,
    required this.confidence,
    required this.version,
    required this.sources,
    this.watchTotalKcal,
    this.estimatedBasalKcal,
  });

  final double activeKcal;
  final double lowKcal;
  final double highKcal;
  final double confidence;
  final String version;
  final List<String> sources;
  final double? watchTotalKcal;
  final double? estimatedBasalKcal;

  Map<String, dynamic> toJson() => {
        'active': activeKcal,
        'low': lowKcal,
        'high': highKcal,
        'confidence': confidence,
        'version': version,
        'sources': sources,
        if (watchTotalKcal != null) 'watchTotal': watchTotalKcal,
        if (estimatedBasalKcal != null) 'basal': estimatedBasalKcal,
      };
}
