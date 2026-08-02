import 'package:y300/features/composer_shared/domain/models/composer_collapse_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_collapse_bbcode_grammar.dart';

final class ComposerCollapseDocumentParser {
  const ComposerCollapseDocumentParser({
    this.grammar = const ComposerCollapseBbCodeGrammar(),
    this.maxDepth = 16,
  });

  final ComposerCollapseBbCodeGrammar grammar;
  final int maxDepth;

  ComposerCollapseDocument parse(
    String source, {
    ComposerCollapseIdentityFactory? identityFactory,
  }) {
    final factory = identityFactory ?? ComposerCollapseIdentityFactory();
    if (!grammar.looksLikeCollapseMarkup(source)) {
      return ComposerCollapseDocument(
        source: source,
        parts: [ComposerCollapseText(source)],
      );
    }

    try {
      final parsed = _parseRange(source, 0, source.length, 0, factory);
      return ComposerCollapseDocument(
        source: source,
        parts: parsed.parts,
        issues: parsed.issues,
        isLossless: true,
      );
    } on _CollapseParseFailure catch (failure) {
      return ComposerCollapseDocument(
        source: source,
        parts: [ComposerCollapseText(source)],
        issues: [failure.issue],
        isLossless: false,
      );
    }
  }

  _ParseRange _parseRange(
    String source,
    int start,
    int end,
    int depth,
    ComposerCollapseIdentityFactory factory,
  ) {
    final parts = <ComposerCollapsePart>[];
    final issues = <ComposerCollapseParseIssue>[];
    var cursor = start;
    var textStart = start;

    while (cursor < end) {
      final next = _nextMarker(source, cursor, end);
      if (next == null) {
        if (grammar.looksLikeCollapseMarkup(source.substring(cursor, end))) {
          throw _CollapseParseFailure(
            _issueForMalformedMarkup(source, cursor, end),
          );
        }
        break;
      }
      if (next is _ClosingMarker) {
        throw _CollapseParseFailure(
          ComposerCollapseParseIssue(
            code: ComposerCollapseParseIssueCode.unexpectedClosing,
            offset: next.closing.start,
          ),
        );
      }
      final opening = (next as _OpeningMarker).opening;
      if (!grammar.isValidTitle(opening.title)) {
        throw _CollapseParseFailure(
          ComposerCollapseParseIssue(
            code: ComposerCollapseParseIssueCode.malformedOpening,
            offset: opening.start,
          ),
        );
      }
      if (depth >= maxDepth) {
        throw _CollapseParseFailure(
          ComposerCollapseParseIssue(
            code: ComposerCollapseParseIssueCode.maximumDepthExceeded,
            offset: opening.start,
          ),
        );
      }
      final closing = _findClosing(source, opening.bodyStart, end);
      final body = _parseRange(
        source,
        opening.bodyStart,
        closing.start,
        depth + 1,
        factory,
      );
      if (opening.start > textStart) {
        parts.add(
          ComposerCollapseText(source.substring(textStart, opening.start)),
        );
      }
      parts.add(
        ComposerCollapseBlock(
          id: factory.next(),
          title: opening.title,
          body: ComposerCollapseDocument(
            source: source.substring(opening.bodyStart, closing.start),
            parts: body.parts,
            issues: body.issues,
          ),
          mode: opening.mode,
          rawOpeningLine: opening.rawOpeningLine,
          rawClosing: closing.raw,
        ),
      );
      issues.addAll(body.issues);
      cursor = closing.end;
      textStart = cursor;
    }

    final trailingClosing = _closingAt(source, cursor, end);
    if (trailingClosing != null) {
      throw _CollapseParseFailure(
        ComposerCollapseParseIssue(
          code: ComposerCollapseParseIssueCode.unexpectedClosing,
          offset: trailingClosing.start,
        ),
      );
    }
    if (textStart < end) {
      parts.add(ComposerCollapseText(source.substring(textStart, end)));
    }
    return _ParseRange(parts: parts, issues: issues);
  }

  _Marker? _nextMarker(String source, int cursor, int end) {
    final opening = ComposerCollapseBbCodeGrammar.openingPattern.firstMatch(
      source.substring(cursor, end),
    );
    final closing = ComposerCollapseBbCodeGrammar.closingPattern.firstMatch(
      source.substring(cursor, end),
    );
    if (opening == null && closing == null) {
      return null;
    }
    final openingStart = opening == null ? null : cursor + opening.start;
    final closingStart = closing == null ? null : cursor + closing.start;
    if (closingStart != null &&
        (openingStart == null || closingStart < openingStart)) {
      return _ClosingMarker(
        ComposerCollapseClosingToken(
          start: closingStart,
          end: cursor + closing!.end,
          raw: closing.group(0)!,
        ),
      );
    }
    final at = openingStart!;
    final token = grammar.openingAt(source, at);
    if (token == null) {
      throw _CollapseParseFailure(_issueForOpening(source, at, opening));
    }
    return _OpeningMarker(token);
  }

  ComposerCollapseClosingToken _findClosing(String source, int start, int end) {
    var depth = 1;
    var cursor = start;
    while (cursor < end) {
      final opening = ComposerCollapseBbCodeGrammar.openingPattern.firstMatch(
        source.substring(cursor, end),
      );
      final closing = ComposerCollapseBbCodeGrammar.closingPattern.firstMatch(
        source.substring(cursor, end),
      );
      if (opening == null && closing == null) {
        throw _CollapseParseFailure(
          ComposerCollapseParseIssue(
            code: ComposerCollapseParseIssueCode.missingClosing,
            offset: start,
          ),
        );
      }
      final openingStart = opening == null ? null : cursor + opening.start;
      final closingStart = closing == null ? null : cursor + closing.start;
      if (closingStart != null &&
          (openingStart == null || closingStart < openingStart)) {
        depth -= 1;
        final token = ComposerCollapseClosingToken(
          start: closingStart,
          end: cursor + closing!.end,
          raw: closing.group(0)!,
        );
        if (depth == 0) {
          return token;
        }
        cursor = token.end;
      } else {
        final token = grammar.openingAt(source, openingStart!);
        if (token == null) {
          throw _CollapseParseFailure(
            _issueForOpening(source, openingStart, opening),
          );
        }
        depth += 1;
        cursor = token.bodyStart;
      }
    }
    throw _CollapseParseFailure(
      ComposerCollapseParseIssue(
        code: ComposerCollapseParseIssueCode.missingClosing,
        offset: start,
      ),
    );
  }

  ComposerCollapseParseIssue _issueForMalformedMarkup(
    String source,
    int start,
    int end,
  ) {
    final match = ComposerCollapseBbCodeGrammar.collapseLikePattern.firstMatch(
      source.substring(start, end),
    );
    final offset = match == null ? start : start + match.start;
    return _issueForOpening(source, offset, null);
  }

  ComposerCollapseParseIssue _issueForOpening(
    String source,
    int offset,
    RegExpMatch? opening,
  ) {
    final mode = opening?.group(1);
    return ComposerCollapseParseIssue(
      code: mode != null && ComposerCollapseMode.fromWireValue(mode) == null
          ? ComposerCollapseParseIssueCode.unsupportedMode
          : ComposerCollapseParseIssueCode.malformedOpening,
      offset: offset,
    );
  }

  ComposerCollapseClosingToken? _closingAt(String source, int offset, int end) {
    final token = grammar.closingAt(source, offset);
    return token != null && token.end <= end ? token : null;
  }
}

sealed class _Marker {
  const _Marker();
}

final class _OpeningMarker extends _Marker {
  const _OpeningMarker(this.opening);

  final ComposerCollapseOpeningToken opening;
}

final class _ClosingMarker extends _Marker {
  const _ClosingMarker(this.closing);

  final ComposerCollapseClosingToken closing;
}

final class _ParseRange {
  const _ParseRange({required this.parts, required this.issues});

  final List<ComposerCollapsePart> parts;
  final List<ComposerCollapseParseIssue> issues;
}

final class _CollapseParseFailure implements Exception {
  const _CollapseParseFailure(this.issue);

  final ComposerCollapseParseIssue issue;
}
