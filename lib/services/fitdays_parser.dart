import '../models/body_composition.dart';

class FitdaysParseResult {
  const FitdaysParseResult({
    required this.entry,
    required this.confidence,
    required this.warnings,
  });

  final BodyCompositionEntry entry;
  final Map<String, double> confidence;
  final List<String> warnings;

  bool get needsReview => warnings.isNotEmpty || confidence.values.any((value) => value < 0.8);
}

class FitdaysParser {
  const FitdaysParser();

  FitdaysParseResult parse(
    String rawText, {
    String? sourceImagePath,
    String? fingerprint,
  }) {
    final text = _normalise(rawText);
    final lines = text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    final values = <String, double>{};
    final confidence = <String, double>{};
    final warnings = <String>[];

    void readFirst(String key, List<String> labels, {double certainty = 0.9}) {
      final line = _lineFor(lines, labels);
      final numbers = line == null ? const <double>[] : _numbers(line);
      if (numbers.isNotEmpty) {
        values[key] = numbers.first;
        confidence[key] = certainty;
      }
    }

    void readFirstLast(String firstKey, String lastKey, List<String> labels) {
      final line = _lineFor(lines, labels);
      final numbers = line == null ? const <double>[] : _numbers(line);
      if (numbers.isNotEmpty) {
        values[firstKey] = numbers.first;
        confidence[firstKey] = 0.9;
      }
      if (numbers.length >= 2) {
        values[lastKey] = numbers.last;
        confidence[lastKey] = numbers.length >= 4 ? 0.88 : 0.72;
      }
    }

    readFirst('weightKg', ['peso ']);
    readFirstLast('bodyFatKg', 'bodyFatPct', ['grasa corporal']);
    readFirstLast('boneMassKg', 'boneMassPct', ['masa esqueletica']);
    readFirstLast('proteinKg', 'proteinPct', ['cantidad de proteina']);
    readFirstLast('waterKg', 'waterPct', ['contenido de agua']);
    readFirstLast('muscleMassKg', 'muscleMassPct', ['masa muscular']);
    readFirstLast('skeletalMuscleKg', 'skeletalMusclePct', ['musculo esqueletico']);
    readFirst('score', ['puntuacion corporal']);
    readFirst('targetWeightKg', ['peso objetivo recomendado']);
    readFirst('weightControlKg', ['control de peso']);
    readFirst('fatControlKg', ['control de grasa']);
    readFirst('muscleControlKg', ['control muscular']);
    readFirst('bmi', ['imc']);
    readFirst('obesityPct', ['obesidad(peso actual/peso objetivo)', 'obesidad peso actual']);
    readFirst('visceralFatGrade', ['grado de grasa visceral']);
    readFirst('bmrKcal', ['tasa metabolica basal']);
    readFirst('fatFreeMassKg', ['peso corporal sin grasa']);
    readFirst('subcutaneousFatPct', ['grasa subcutanea']);
    readFirst('asmi', ['asmi']);
    readFirst('bodyAge', ['edad corporal']);
    readFirst('whr', ['whr']);

    final measuredAt = _readDate(text);
    if (measuredAt == null) warnings.add('No se pudo leer la fecha de medición.');
    for (final required in ['weightKg', 'bodyFatPct', 'muscleMassKg', 'bmi']) {
      if (!values.containsKey(required)) warnings.add('Falta ${_friendly(required)}.');
    }
    _validate(values, confidence, warnings);

    final at = measuredAt ?? DateTime.now();
    final id = 'fitdays-${at.microsecondsSinceEpoch}';
    return FitdaysParseResult(
      entry: BodyCompositionEntry(
        id: id,
        measuredAt: at,
        source: 'fitdays_ocr',
        values: values,
        sourceFingerprint: fingerprint,
        sourceImagePath: sourceImagePath,
      ),
      confidence: confidence,
      warnings: warnings,
    );
  }

  static String _normalise(String value) {
    var text = value.toLowerCase().replaceAll(',', '.');
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
    accents.forEach((from, to) => text = text.replaceAll(from, to));
    return text.replaceAll(RegExp(r'[ \t]+'), ' ');
  }

  static String? _lineFor(List<String> lines, List<String> labels) {
    for (final label in labels) {
      for (final line in lines) {
        if (line.startsWith(label) || line.contains('$label ')) return line.substring(line.indexOf(label) + label.length);
      }
    }
    return null;
  }

  static List<double> _numbers(String line) => RegExp(r'-?\d+(?:\.\d+)?')
      .allMatches(line)
      .map((match) => double.parse(match.group(0)!))
      .toList();

  static DateTime? _readDate(String text) {
    final match = RegExp(
      r'(?:hora de la prueba\s*:?\s*)?(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(text);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final hour = int.tryParse(match.group(4) ?? '') ?? 12;
    final minute = int.tryParse(match.group(5) ?? '') ?? 0;
    final second = int.tryParse(match.group(6) ?? '') ?? 0;
    final value = DateTime(year, month, day, hour, minute, second);
    return value.year == year && value.month == month && value.day == day ? value : null;
  }

  static void _validate(
    Map<String, double> values,
    Map<String, double> confidence,
    List<String> warnings,
  ) {
    const ranges = <String, (double, double)>{
      'weightKg': (25, 350),
      'bodyFatPct': (2, 70),
      'muscleMassKg': (10, 200),
      'waterPct': (20, 80),
      'bmi': (10, 80),
      'bmrKcal': (500, 5000),
      'whr': (0.4, 2),
    };
    for (final item in ranges.entries) {
      final value = values[item.key];
      if (value == null) continue;
      if (value < item.value.$1 || value > item.value.$2) {
        confidence[item.key] = 0.2;
        warnings.add('${_friendly(item.key)} parece fuera de rango ($value).');
      }
    }
  }

  static String _friendly(String key) => switch (key) {
        'weightKg' => 'peso',
        'bodyFatPct' => 'grasa corporal',
        'muscleMassKg' => 'masa muscular',
        'bmi' => 'IMC',
        'waterPct' => 'agua corporal',
        'bmrKcal' => 'metabolismo basal',
        'whr' => 'WHR',
        _ => key,
      };
}
