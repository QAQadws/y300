/// A complete HTTP(S) URL occurrence in the original string. Offsets are UTF-16
/// code units, not DOM coordinates, code points or reader semantic offsets.
final class ForumHttpTextLink {
  const ForumHttpTextLink({
    required this.start,
    required this.end,
    required this.text,
    required this.uri,
  });

  final int start;
  final int end;
  final String text;
  final Uri uri;
}

final class ForumHttpTextLinkScanResult {
  ForumHttpTextLinkScanResult({
    required Iterable<ForumHttpTextLink> links,
    required this.isLimited,
  }) : links = List<ForumHttpTextLink>.unmodifiable(links);

  /// Occurrences in source order; repeated URLs intentionally remain separate.
  final List<ForumHttpTextLink> links;

  /// Callers requiring a unique target must ignore a limited scan completely.
  /// No URL is emitted from a truncated input or overlong candidate.
  final bool isLimited;
}

/// Bounded, source-preserving URL detection without routing or platform access.
final class ForumHttpTextLinkDetector {
  const ForumHttpTextLinkDetector();

  ForumHttpTextLinkScanResult detect(
    String text, {
    int maxInputLength = 64 * 1024,
    int maxCandidates = 10,
    int maxUrlLength = 8 * 1024,
  }) {
    if (maxInputLength <= 0 || maxCandidates <= 0 || maxUrlLength <= 0) {
      throw ArgumentError('URL scan limits must be positive');
    }
    if (text.length > maxInputLength) {
      return ForumHttpTextLinkScanResult(links: const [], isLimited: true);
    }
    final links = <ForumHttpTextLink>[];
    var limited = false;
    var index = 0;
    while (index < text.length) {
      final schemeLength = _schemeLengthAt(text, index);
      if (schemeLength == 0 || !_hasStartBoundary(text, index)) {
        index++;
        continue;
      }
      final start = index;
      var end = start + schemeLength;
      while (end < text.length && !_isTextDelimiter(text.codeUnitAt(end))) {
        // Comma-separated URLs remain distinct, while ?next=https://... is
        // retained as part of the surrounding URL's query.
        if (_schemeLengthAt(text, end) != 0 &&
            end > start + schemeLength &&
            _isTrailingPunctuation(text.codeUnitAt(end - 1))) {
          break;
        }
        end++;
      }
      index = end;
      if (_hasHardLineContinuation(text, end)) continue;
      if (end - start > maxUrlLength) {
        limited = true;
        continue;
      }
      end = _trimEnd(text, start, end);
      final candidate = text.substring(start, end);
      final uri = _parseCompleteHttpUrl(candidate);
      if (uri == null) continue;
      if (links.length == maxCandidates) {
        limited = true;
        break;
      }
      links.add(
        ForumHttpTextLink(start: start, end: end, text: candidate, uri: uri),
      );
    }
    return ForumHttpTextLinkScanResult(links: links, isLimited: limited);
  }

  /// Literal source whitespace
  /// interrupts a URL; visual wrapping does not change the source string.
  static bool _isTextDelimiter(int unit) =>
      _isWhitespace(unit) ||
      const <int>{
        0x22, 0x27, 0x3C, 0x3E, 0x60, // ASCII quotes and markup boundaries.
        0x2018, 0x2019, 0x201C, 0x201D,
        0x3001, 0x3002, 0x3008, 0x3009, 0x300A, 0x300B,
        0x300C, 0x300D, 0x300E, 0x300F,
        0xFF0C, 0xFF01, 0xFF1F, 0xFF1B, 0xFF1A,
        0xFF08, 0xFF09, 0x3010, 0x3011,
      }.contains(unit);

  static bool _isWhitespace(int unit) =>
      unit <= 0x20 ||
      unit == 0x7F ||
      unit == 0xA0 ||
      (unit >= 0x2000 && unit <= 0x200B) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000;

  static int _schemeLengthAt(String text, int index) {
    if (!_asciiStartsWith(text, index, 'http')) return 0;
    var end = index + 4;
    if (end < text.length && (text.codeUnitAt(end) | 0x20) == 0x73) end++;
    if (end + 3 > text.length || text.substring(end, end + 3) != '://') {
      return 0;
    }
    return end + 3 - index;
  }

  static bool _asciiStartsWith(String text, int index, String pattern) {
    if (index + pattern.length > text.length) return false;
    for (var offset = 0; offset < pattern.length; offset++) {
      if ((text.codeUnitAt(index + offset) | 0x20) !=
          pattern.codeUnitAt(offset)) {
        return false;
      }
    }
    return true;
  }

  static bool _hasStartBoundary(String text, int index) {
    if (index == 0) return true;
    for (final prefix in const ['javascript:', 'vbscript:', 'data:', 'file:']) {
      if (index >= prefix.length &&
          _asciiStartsWith(text, index - prefix.length, prefix)) {
        return false;
      }
    }
    final previous = text.codeUnitAt(index - 1);
    return !((previous >= 0x30 && previous <= 0x39) ||
        (previous >= 0x41 && previous <= 0x5A) ||
        (previous >= 0x61 && previous <= 0x7A) ||
        previous == 0x5F ||
        previous == 0x2F ||
        previous == 0x5C ||
        previous == 0x2D);
  }

  static bool _isTrailingPunctuation(int unit) =>
      unit == 0x2E || // .
      unit == 0x2C || // ,
      unit == 0x21 || // !
      unit == 0x3F || // ?
      unit == 0x3B || // ;
      unit == 0x3A; // :

  static bool _hasHardLineContinuation(String text, int end) {
    if (end == text.length || !_isHardLineBreak(text.codeUnitAt(end))) {
      return false;
    }
    var next = end + 1;
    while (next < text.length && _isWhitespace(text.codeUnitAt(next))) {
      next++;
    }
    if (next == text.length || _schemeLengthAt(text, next) != 0) return false;
    final nextUnit = text.codeUnitAt(next);
    final previousUnit = text.codeUnitAt(end - 1);
    const continuations = <int>{
      0x2E,
      0x2F,
      0x2D,
      0x5F,
      0x25,
      0x3F,
      0x26,
      0x3D,
      0x23,
    };
    final nextAsciiWord =
        (nextUnit >= 0x30 && nextUnit <= 0x39) ||
        (nextUnit >= 0x41 && nextUnit <= 0x5A) ||
        (nextUnit >= 0x61 && nextUnit <= 0x7A);
    // These edges strongly indicate a source-split URL. Do not repair it, or
    // emit its otherwise syntactically valid prefix as a different destination.
    return continuations.contains(nextUnit) ||
        (continuations.contains(previousUnit) && nextAsciiWord);
  }

  static bool _isHardLineBreak(int unit) =>
      unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029;

  static int _trimEnd(String text, int start, int end) {
    var parentheses = 0;
    var brackets = 0;
    var braces = 0;
    for (var index = start; index < end; index++) {
      switch (text.codeUnitAt(index)) {
        case 0x28:
          parentheses++;
        case 0x29:
          parentheses--;
        case 0x5B:
          brackets++;
        case 0x5D:
          brackets--;
        case 0x7B:
          braces++;
        case 0x7D:
          braces--;
      }
    }
    while (end > start) {
      final last = text.codeUnitAt(end - 1);
      if (_isTrailingPunctuation(last)) {
        end--;
      } else if (last == 0x29 && parentheses < 0) {
        parentheses++;
        end--;
      } else if (last == 0x5D && brackets < 0) {
        brackets++;
        end--;
      } else if (last == 0x7D && braces < 0) {
        braces++;
        end--;
      } else {
        break;
      }
    }
    return end;
  }

  static Uri? _parseCompleteHttpUrl(String candidate) {
    // Uri.parse repairs some invalid input (notably backslashes and malformed
    // percent escapes). Detection must not silently create a different URL.
    for (var index = 0; index < candidate.length; index++) {
      final unit = candidate.codeUnitAt(index);
      if (unit == 0x5C) return null;
      if (unit == 0x25) {
        if (index + 2 >= candidate.length ||
            !_isHex(candidate.codeUnitAt(index + 1)) ||
            !_isHex(candidate.codeUnitAt(index + 2))) {
          return null;
        }
        index += 2;
      }
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final host = uri.host;
    if (host.contains(':')) {
      return uri; // Uri has already validated IPv6 syntax.
    }
    if (host == 'localhost') return uri;
    // Do not turn a scheme-only or partially selected hostname into a link.
    final labels = host.split('.');
    if (labels.length < 2 || labels.any((label) => label.isEmpty)) return null;
    for (final label in labels) {
      if (label.startsWith('-') || label.endsWith('-')) return null;
      for (final unit in label.codeUnits) {
        if (!((unit >= 0x30 && unit <= 0x39) ||
            (unit >= 0x61 && unit <= 0x7A) ||
            unit == 0x2D ||
            unit >= 0x80)) {
          return null;
        }
      }
    }
    return uri;
  }

  static bool _isHex(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x46) ||
      (unit >= 0x61 && unit <= 0x66);
}
