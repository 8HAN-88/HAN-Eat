/// Разбор количества в строках ингредиентов (г, кг, мл, шт).
class ParsedIngredient {
  const ParsedIngredient({
    required this.name,
    this.amount,
    this.unit,
    this.portions = 1,
  });

  final String name;
  final double? amount;
  final String? unit;
  final int portions;

  String? get displayQuantity {
    if (amount != null && unit != null) {
      final val = amount!;
      final valS = val == val.roundToDouble()
          ? '${val.round()}'
          : val.toStringAsFixed(1).replaceAll('.', ',');
      return '$valS ${_unitLabel(unit!)}';
    }
    if (portions > 1) return '×$portions порц.';
    return null;
  }

  static String _unitLabel(String unit) => switch (unit) {
        'g' => 'г',
        'ml' => 'мл',
        'pcs' => 'шт',
        'tbsp' => 'ст. л.',
        'tsp' => 'ч. л.',
        'clove' => 'зуб.',
        'bunch' => 'пучок',
        'cup' => 'стак.',
        _ => unit,
      };
}

final _patterns = <({RegExp re, String unit, bool scaleToBase})>[
  (re: RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:кг|kg)\b', caseSensitive: false), unit: 'g', scaleToBase: true),
  (re: RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:г|гр|грамм\w*)\b', caseSensitive: false), unit: 'g', scaleToBase: false),
  (re: RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:мл|ml)\b', caseSensitive: false), unit: 'ml', scaleToBase: false),
  (re: RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:л|l)\b', caseSensitive: false), unit: 'ml', scaleToBase: true),
  (re: RegExp(r'(\d+)\s*(?:шт\.?|штук\w*)\b', caseSensitive: false), unit: 'pcs', scaleToBase: false),
  (re: RegExp(r'(\d+)\s*(?:ст\.?\s*л\.?|столов\w*\s*ложк\w*)\b', caseSensitive: false), unit: 'tbsp', scaleToBase: false),
  (re: RegExp(r'(\d+)\s*(?:ч\.?\s*л\.?|чайн\w*\s*ложк\w*)\b', caseSensitive: false), unit: 'tsp', scaleToBase: false),
  (re: RegExp(r'(\d+)\s*(?:зубч\.?|зубчик\w*)\b', caseSensitive: false), unit: 'clove', scaleToBase: false),
];

ParsedIngredient parseIngredientLine(String line) {
  var working = line.trim();
  if (working.isEmpty) return const ParsedIngredient(name: '');

  double? amount;
  String? unit;

  for (final p in _patterns) {
    final m = p.re.firstMatch(working);
    if (m == null) continue;
    amount = double.parse(m.group(1)!.replaceAll(',', '.'));
    if (p.scaleToBase) {
      amount = p.unit == 'g' ? amount * 1000 : amount * 1000;
    }
    unit = p.unit;
    working = '${working.substring(0, m.start)}${working.substring(m.end)}'
        .trim()
        .replaceAll(RegExp(r'^[\s,\-–—]+'), '')
        .replaceAll(RegExp(r'[\s,\-–—]+$'), '');
    break;
  }

  var name = working.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) name = line.trim();
  return ParsedIngredient(name: name, amount: amount, unit: unit);
}

String _normalizeName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Объединить строки ингредиентов для списка покупок.
List<({String name, String? quantity})> mergeIngredientLines(
  List<String> lines, {
  int portions = 1,
}) {
  final factor = portions < 1 ? 1 : portions;
  final merged = <String, ParsedIngredient>{};

  for (final line in lines) {
    var parsed = parseIngredientLine(line);
    if (parsed.amount != null && parsed.unit != null) {
      if (factor != 1) {
        parsed = ParsedIngredient(
          name: parsed.name,
          amount: (parsed.amount! * factor * 10).round() / 10,
          unit: parsed.unit,
        );
      }
    } else {
      parsed = ParsedIngredient(
        name: parsed.name,
        portions: factor,
      );
    }
    final key = parsed.unit != null
        ? '${_normalizeName(parsed.name)}|${parsed.unit}'
        : _normalizeName(parsed.name);
    if (parsed.name.isEmpty) continue;

    final prev = merged[key];
    if (prev == null) {
      merged[key] = parsed;
      continue;
    }
    if (prev.amount != null &&
        parsed.amount != null &&
        prev.unit == parsed.unit) {
      merged[key] = ParsedIngredient(
        name: prev.name,
        amount: prev.amount! + parsed.amount!,
        unit: prev.unit,
      );
    } else if (prev.amount == null && parsed.amount == null) {
      merged[key] = ParsedIngredient(
        name: prev.name,
        portions: prev.portions + parsed.portions,
      );
    } else {
      merged['$key#${merged.length}'] = parsed;
    }
  }

  return merged.values
      .map((p) => (
            name: p.name.isEmpty
                ? p.name
                : p.name[0].toUpperCase() + p.name.substring(1),
            quantity: p.displayQuantity,
          ))
      .toList();
}
