class SegmentalValue {
  const SegmentalValue({this.kg, this.percent, this.evaluation});

  final double? kg;
  final double? percent;
  final String? evaluation;

  Map<String, dynamic> toJson() => {
        if (kg != null) 'kg': kg,
        if (percent != null) 'pct': percent,
        if (evaluation != null) 'eval': evaluation,
      };

  factory SegmentalValue.fromJson(Map<String, dynamic> j) => SegmentalValue(
        kg: (j['kg'] as num?)?.toDouble(),
        percent: (j['pct'] as num?)?.toDouble(),
        evaluation: j['eval'] as String?,
      );
}

class BodyCompositionEntry {
  const BodyCompositionEntry({
    required this.id,
    required this.measuredAt,
    required this.source,
    required this.values,
    this.segmentalFat = const {},
    this.segmentalMuscle = const {},
    this.impedance20Khz = const {},
    this.impedance100Khz = const {},
    this.evaluations = const {},
    this.sourceFingerprint,
    this.sourceImagePath,
    this.healthConnectId,
  });

  final String id;
  final DateTime measuredAt;
  final String source;
  final Map<String, double> values;
  final Map<String, SegmentalValue> segmentalFat;
  final Map<String, SegmentalValue> segmentalMuscle;
  final Map<String, double> impedance20Khz;
  final Map<String, double> impedance100Khz;
  final Map<String, String> evaluations;
  final String? sourceFingerprint;
  final String? sourceImagePath;
  final String? healthConnectId;

  double? operator [](String key) => values[key];

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': measuredAt.toIso8601String(),
        'source': source,
        'values': values,
        'fat': segmentalFat.map((k, v) => MapEntry(k, v.toJson())),
        'muscle': segmentalMuscle.map((k, v) => MapEntry(k, v.toJson())),
        'z20': impedance20Khz,
        'z100': impedance100Khz,
        'eval': evaluations,
        if (sourceFingerprint != null) 'fingerprint': sourceFingerprint,
        if (sourceImagePath != null) 'image': sourceImagePath,
        if (healthConnectId != null) 'healthId': healthConnectId,
      };

  factory BodyCompositionEntry.fromJson(Map<String, dynamic> j) => BodyCompositionEntry(
        id: j['id'] as String,
        measuredAt: DateTime.parse(j['at'] as String),
        source: (j['source'] as String?) ?? 'manual',
        values: ((j['values'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        segmentalFat: _segments(j['fat']),
        segmentalMuscle: _segments(j['muscle']),
        impedance20Khz: _numbers(j['z20']),
        impedance100Khz: _numbers(j['z100']),
        evaluations: ((j['eval'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as String)),
        sourceFingerprint: j['fingerprint'] as String?,
        sourceImagePath: j['image'] as String?,
        healthConnectId: j['healthId'] as String?,
      );

  static Map<String, double> _numbers(Object? raw) => ((raw as Map?) ?? const {})
      .map((k, v) => MapEntry(k as String, (v as num).toDouble()));

  static Map<String, SegmentalValue> _segments(Object? raw) => ((raw as Map?) ?? const {})
      .map((k, v) => MapEntry(k as String,
          SegmentalValue.fromJson((v as Map).cast<String, dynamic>())));
}

const bodyCompositionKeys = <String>{
  'weightKg',
  'bodyFatKg',
  'bodyFatPct',
  'boneMassKg',
  'proteinKg',
  'proteinPct',
  'waterKg',
  'waterPct',
  'muscleMassKg',
  'muscleMassPct',
  'skeletalMuscleKg',
  'skeletalMusclePct',
  'score',
  'targetWeightKg',
  'weightControlKg',
  'fatControlKg',
  'muscleControlKg',
  'bmi',
  'obesityPct',
  'visceralFatGrade',
  'bmrKcal',
  'fatFreeMassKg',
  'subcutaneousFatPct',
  'asmi',
  'bodyAge',
  'whr',
};
