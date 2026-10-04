/// Discuz editor font sizes are 1..7 with size 3 as the normal body size.
final class DiscuzFontSizePolicy {
  const DiscuzFontSizePolicy._();

  static const int normalSize = 3;
  static const int minSize = 1;
  static const int maxSize = 7;

  static const Map<int, double> scales = <int, double>{
    1: 0.75,
    2: 0.875,
    3: 1.0,
    4: 1.125,
    5: 1.25,
    6: 1.5,
    7: 1.75,
  };

  static int? normalize(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < minSize || parsed > maxSize) {
      return null;
    }
    return parsed;
  }

  static double? scaleFor(Object? value) {
    final normalized = normalize(value);
    return normalized == null ? null : scales[normalized];
  }

  static String? cssPercentFor(Object? value) {
    final scale = scaleFor(value);
    if (scale == null) {
      return null;
    }
    return '${_formatNumber(scale * 100)}%';
  }

  static double? fontSizeForBase(
    Object? value, {
    required double baseFontSize,
  }) {
    final scale = scaleFor(value);
    if (scale == null) {
      return null;
    }
    return baseFontSize * scale;
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
