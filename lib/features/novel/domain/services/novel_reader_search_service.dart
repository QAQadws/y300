import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_text_coordinates.dart';

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
      for (final match in pattern.allMatches(text)) {
        textIdentity ??= NovelReaderAnchorFormat.textIdentity(text);
        results.add(
          NovelReaderSearchResult(
            resultId: '${document.episodeId}:${block.anchorId}:$globalIndex',
            keyword: normalizedKeyword,
            anchor: NovelReaderTextAnchor(
              episodeId: document.episodeId,
              nodeId: block.anchorId,
              textOffset: NovelReaderTextCoordinates.codePointOffsetForUtf16(
                text,
                match.start,
              ),
              formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
              textIdentity: textIdentity,
              isProgressPercentValid: false,
            ),
            snippet: NovelReaderTextCoordinates.snippet(
              text: text,
              start: match.start,
              end: match.end,
              contextLength: contextLength,
            ),
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
