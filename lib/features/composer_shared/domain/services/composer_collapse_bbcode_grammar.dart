import 'package:y300/features/composer_shared/domain/models/composer_collapse_models.dart';

final class ComposerCollapseOpeningToken {
  const ComposerCollapseOpeningToken({
    required this.start,
    required this.headerEnd,
    required this.bodyStart,
    required this.rawOpeningLine,
    required this.title,
    required this.mode,
  });

  final int start;
  final int headerEnd;
  final int bodyStart;
  final String rawOpeningLine;
  final String title;
  final ComposerCollapseMode mode;
}

final class ComposerCollapseClosingToken {
  const ComposerCollapseClosingToken({
    required this.start,
    required this.end,
    required this.raw,
  });

  final int start;
  final int end;
  final String raw;
}

/// Discuz collapse grammar. This intentionally accepts only mode 0.
final class ComposerCollapseBbCodeGrammar {
  const ComposerCollapseBbCodeGrammar();

  static final RegExp openingPattern = RegExp(
    r'\[collapse[ \t]*=[ \t]*([^,\]\r\n]+),([^\]\r\n]*)\]',
    caseSensitive: false,
  );
  static final RegExp closingPattern = RegExp(
    r'\[/collapse[ \t]*\]',
    caseSensitive: false,
  );
  static final RegExp collapseLikePattern = RegExp(
    r'\[/?collapse(?:\s*=\s*[^\]]*)?\]',
    caseSensitive: false,
  );

  ComposerCollapseOpeningToken? openingAt(String source, int offset) {
    if (offset < 0 ||
        offset >= source.length ||
        (offset > 0 && source.codeUnitAt(offset - 1) != 0x0A)) {
      return null;
    }
    final match = openingPattern.matchAsPrefix(source, offset);
    if (match == null) {
      return null;
    }
    final mode = ComposerCollapseMode.fromWireValue(match.group(1)!);
    if (mode == null) {
      return null;
    }
    final headerEnd = match.end;
    final lineEndingLength = _lineEndingLengthAt(source, headerEnd);
    if (lineEndingLength == null) {
      return null;
    }
    final bodyStart = headerEnd + lineEndingLength;
    final title = match.group(2)!;
    return ComposerCollapseOpeningToken(
      start: match.start,
      headerEnd: headerEnd,
      bodyStart: bodyStart,
      rawOpeningLine: source.substring(match.start, bodyStart),
      title: title,
      mode: mode,
    );
  }

  ComposerCollapseClosingToken? closingAt(String source, int offset) {
    final match = closingPattern.matchAsPrefix(source, offset);
    if (match == null) {
      return null;
    }
    return ComposerCollapseClosingToken(
      start: match.start,
      end: match.end,
      raw: match.group(0)!,
    );
  }

  bool looksLikeCollapseMarkup(String source) {
    return collapseLikePattern.hasMatch(source);
  }

  bool isValidTitle(String title) {
    return !title.contains(']') &&
        !title.contains('\r') &&
        !title.contains('\n') &&
        !title.contains('\uFFFC');
  }

  int? _lineEndingLengthAt(String source, int offset) {
    if (offset >= source.length) {
      return null;
    }
    if (source.codeUnitAt(offset) == 0x0A) {
      return 1;
    }
    if (source.codeUnitAt(offset) == 0x0D &&
        offset + 1 < source.length &&
        source.codeUnitAt(offset + 1) == 0x0A) {
      return 2;
    }
    return null;
  }
}
