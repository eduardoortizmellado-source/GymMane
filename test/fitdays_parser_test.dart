import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/services/fitdays_parser.dart';

void main() {
  const parser = FitdaysParser();

  test('parses the latest supplied Fitdays report fields', () {
    const text = '''
Informe de análisis de composición corporal
Hora de la prueba:07/10/2026 12:34:02
Peso 75.4 (54.7-74.0) 100.0 Alto
Grasa corporal 17.3 (7.7-15.4) 23.0 Alto
Masa Esquelética 3.9 (3.1-3.9) 5.2 Excelente
Cantidad de proteína 11.6 (9.4-11.7) 15.4 Estándar
Contenido de agua 42.5 (34.5-43.0) 56.4 Estándar
Masa muscular 54.1 (43.9-54.7) 71.8 Estándar
Músculo esquelético 32.8 (27.4-33.5) 43.5 Estándar
Puntuación corporal 76 /100 Puntos
Peso objetivo recomendado 67.7 kg
Control de peso -7.7 kg
Control de grasa -7.7 kg
Control muscular 0.0 kg
IMC 25.8
Obesidad(peso actual/peso objetivo) 117%
Grado de grasa visceral 6
Tasa metabólica basal 1622 kcal
Peso corporal sin grasa 58.0 kg
Grasa subcutánea 16.5 %
ASMI 8.6 kg/m²
Edad corporal 23
WHR 0.89
''';
    final parsed = parser.parse(text, fingerprint: 'golden-2026-10-07');

    expect(parsed.entry.measuredAt, DateTime(2026, 10, 7, 12, 34, 2));
    expect(parsed.entry['weightKg'], 75.4);
    expect(parsed.entry['bodyFatKg'], 17.3);
    expect(parsed.entry['bodyFatPct'], 23.0);
    expect(parsed.entry['muscleMassKg'], 54.1);
    expect(parsed.entry['skeletalMuscleKg'], 32.8);
    expect(parsed.entry['bmrKcal'], 1622);
    expect(parsed.entry['whr'], 0.89);
    expect(parsed.warnings, isEmpty);
  });

  test('four report dates remain distinct for bulk import deduplication', () {
    final dates = [
      '15/09/2026 13:10:45',
      '24/09/2026 11:52:44',
      '28/09/2026 11:32:44',
      '07/10/2026 12:34:02',
    ];
    final ids = dates.map((date) => parser.parse('''
Hora de la prueba:$date
Peso 75.5
Grasa corporal 18.0 23.9
Masa muscular 53.6
IMC 25.8
''').entry.id).toSet();
    expect(ids, hasLength(4));
  });

  test('suspicious OCR values are retained but forced through review', () {
    final result = parser.parse('''
Hora de la prueba:07/10/2026 12:34:02
Peso 754
Grasa corporal 17.3 230
Masa muscular 54.1
IMC 258
''');
    expect(result.needsReview, true);
    expect(result.confidence['weightKg'], 0.2);
    expect(result.warnings, isNotEmpty);
  });
}
