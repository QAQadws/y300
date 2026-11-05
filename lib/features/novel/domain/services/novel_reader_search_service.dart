import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

class NovelReaderSearchService {
  const NovelReaderSearchService();

  List<NovelReaderSearchResult> search({
    required NovelReaderDocument document,
    required String keyword,
    int contextLength = 18,
  }) {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) {
      return const <NovelReaderSearchResult>[];
    }

    final pattern = RegExp(
      RegExp.escape(normalizedKeyword),
      caseSensitive: false,
      unicode: true,
    );
    final results = <NovelReaderSearchResult>[];
    var globalIndex = 0;
    for (final block in document.blocks) {
      final text = block.novelPlainText;
      String? textIdentity;
      _BlockCoordinates? coordinates;
      for (final match in pattern.allMatches(text)) {
        textIdentity ??= NovelReaderAnchorFormat.textIdentity(text);
        final positions = coordinates ??= _BlockCoordinates(text);
        results.add(
          NovelReaderSearchResult(
            resultId: '${document.episodeId}:${block.anchorId}:$globalIndex',
            keyword: normalizedKeyword,
            range: NovelReaderTextRange(
              NovelReaderTextAnchor(
                episodeId: document.episodeId,
                nodeId: block.anchorId,
                textOffset: positions.startCodePoint(match.start),
                formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
                textIdentity: textIdentity,
                isProgressPercentValid: false,
              ),
              positions.endCodePoint(match.end),
            ),
            snippet: positions.snippet(match.start, match.end, contextLength),
            matchStart: match.start,
            matchEnd: match.end,
            nodeId: block.anchorId,
          ),
        );
        globalIndex++;
      }
    }
    return List<NovelReaderSearchResult>.unmodifiable(results);
  }
}

/// Index a matching node once, even when a short keyword occurs many times.
final class _BlockCoordinates {
  _BlockCoordinates(this.text) {
    for (final glyph in text.characters) {
      _utf16.add(_utf16.last + glyph.length);
      _codePoints.add(_codePoints.last + glyph.runes.length);
    }
  }

  final String text;
  final _utf16 = [0];
  final _codePoints = [0];

  int _ceiling(int offset) {
    var low = 0, high = _utf16.length - 1;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_utf16[middle] < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _floor(int offset) {
    final boundary = _ceiling(offset);
    return _utf16[boundary] == offset ? boundary : boundary - 1;
  }

  int startCodePoint(int offset) => _codePoints[_floor(offset)];
  int endCodePoint(int offset) => _codePoints[_ceiling(offset)];

  String snippet(int start, int end, int contextLength) {
    final context = math.max(0, contextLength);
    final from = _utf16[_floor(math.max(0, start - context))];
    final to = _utf16[_ceiling(math.min(text.length, end + context))];
    return '${from == 0 ? '' : '...'}${text.substring(from, to)}'
        '${to == text.length ? '' : '...'}';
  }
}
