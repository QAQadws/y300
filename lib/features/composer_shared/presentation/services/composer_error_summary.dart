abstract final class ComposerErrorSummary {
  static const int _maxLength = 180;

  static String? sanitize(Object? raw) {
    if (raw == null) {
      return null;
    }
    var value = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isEmpty) {
      return null;
    }
    value = value.replaceAll(
      RegExp(r'https?://\S+', caseSensitive: false),
      '[URL]',
    );
    value = value.replaceAll(
      RegExp(
        r'\b(cookie|formhash|uploadhash)\b\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      r'$1=[REDACTED]',
    );
    if (value.length > _maxLength) {
      value = '${value.substring(0, _maxLength - 3)}...';
    }
    return value;
  }
}
