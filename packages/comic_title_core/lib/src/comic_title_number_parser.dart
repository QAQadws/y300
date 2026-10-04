final class ComicTitleNumberParser {
  const ComicTitleNumberParser();

  static const Map<String, int> _circledDigits = <String, int>{
    '①': 1,
    '②': 2,
    '③': 3,
    '④': 4,
    '⑤': 5,
    '⑥': 6,
    '⑦': 7,
    '⑧': 8,
    '⑨': 9,
    '⑩': 10,
    '⑪': 11,
    '⑫': 12,
    '⑬': 13,
    '⑭': 14,
    '⑮': 15,
    '⑯': 16,
    '⑰': 17,
    '⑱': 18,
    '⑲': 19,
    '⑳': 20,
  };

  static const Map<String, int> _unicodeRomanNumbers = <String, int>{
    'Ⅰ': 1,
    'Ⅱ': 2,
    'Ⅲ': 3,
    'Ⅳ': 4,
    'Ⅴ': 5,
    'Ⅵ': 6,
    'Ⅶ': 7,
    'Ⅷ': 8,
    'Ⅸ': 9,
    'Ⅹ': 10,
    'Ⅺ': 11,
    'Ⅻ': 12,
  };

  static const Map<String, int> _chineseDigits = <String, int>{
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '兩': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };

  static const Map<String, int> _chineseUnits = <String, int>{
    '十': 10,
    '百': 100,
    '千': 1000,
  };

  double? parseNumber(String input) {
    final normalized = _normalize(input);
    if (normalized.isEmpty) {
      return null;
    }

    final directNumber = double.tryParse(normalized);
    if (directNumber != null) {
      return directNumber;
    }

    final circled = _circledDigits[normalized];
    if (circled != null) {
      return circled.toDouble();
    }

    final unicodeRoman = _unicodeRomanNumbers[normalized];
    if (unicodeRoman != null) {
      return unicodeRoman.toDouble();
    }

    final roman = _parseRoman(normalized);
    if (roman != null) {
      return roman.toDouble();
    }

    final chinese = _parseChineseNumber(normalized);
    if (chinese != null) {
      return chinese.toDouble();
    }

    return null;
  }

  String _normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.trim().runes) {
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0xFF0E) {
        buffer.write('.');
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().trim();
  }

  int? _parseRoman(String input) {
    if (!RegExp(r'^[IVXLCDM]+$', caseSensitive: false).hasMatch(input)) {
      return null;
    }
    final values = <String, int>{
      'I': 1,
      'V': 5,
      'X': 10,
      'L': 50,
      'C': 100,
      'D': 500,
      'M': 1000,
    };
    final normalized = input.toUpperCase();
    var total = 0;
    var previous = 0;
    for (final rune in normalized.runes.toList().reversed) {
      final value = values[String.fromCharCode(rune)]!;
      if (value < previous) {
        total -= value;
      } else {
        total += value;
        previous = value;
      }
    }
    return total == 0 ? null : total;
  }

  int? _parseChineseNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (!_containsOnlyChineseNumberChars(trimmed)) {
      return null;
    }

    if (!trimmed.contains('十') &&
        !trimmed.contains('百') &&
        !trimmed.contains('千')) {
      final digits = trimmed.split('').map((char) => _chineseDigits[char]);
      if (digits.any((digit) => digit == null)) {
        return null;
      }
      return int.tryParse(digits.map((digit) => digit.toString()).join());
    }

    var total = 0;
    var current = 0;
    for (final char in trimmed.split('')) {
      final digit = _chineseDigits[char];
      if (digit != null) {
        current = digit;
        continue;
      }
      final unit = _chineseUnits[char];
      if (unit == null) {
        return null;
      }
      total += (current == 0 ? 1 : current) * unit;
      current = 0;
    }
    total += current;
    return total == 0 && trimmed != '零' && trimmed != '〇' ? null : total;
  }

  bool _containsOnlyChineseNumberChars(String input) {
    return input
        .split('')
        .every(
          (char) =>
              _chineseDigits.containsKey(char) ||
              _chineseUnits.containsKey(char),
        );
  }
}
