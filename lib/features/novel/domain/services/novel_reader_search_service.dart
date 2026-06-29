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

    final lowerKeyword = normalizedKeyword.toLowerCase();
    final results = <NovelReaderSearchResult>[];
    var globalIndex = 0;
    for (final block in document.blocks) {
      final text = block.novelPlainText;
      final lowerText = text.toLowerCase();
      var start = 0;
      while (start < lowerText.length) {
        final index = lowerText.indexOf(lowerKeyword, start);
        if (index < 0) {
          break;
        }
        final matchEnd = index + normalizedKeyword.length;
        results.add(
          NovelReaderSearchResult(
            resultId: '${document.episodeId}:${block.anchorId}:$globalIndex',
            keyword: normalizedKeyword,
            anchor: NovelReaderTextAnchor(
              episodeId: document.episodeId,
              nodeId: block.anchorId,
              textOffset: index,
            ),
            snippet: _snippet(
              text: text,
              start: index,
              end: matchEnd,
              contextLength: contextLength,
            ),
            matchStart: index,
            matchEnd: matchEnd,
            nodeId: block.anchorId,
          ),
        );
        globalIndex++;
        start = matchEnd;
      }
    }
    return List<NovelReaderSearchResult>.unmodifiable(results);
  }

  String _snippet({
    required String text,
    required int start,
    required int end,
    required int contextLength,
  }) {
    final safeContext = contextLength < 0 ? 0 : contextLength;
    final snippetStart = (start - safeContext).clamp(0, text.length).toInt();
    final snippetEnd = (end + safeContext).clamp(0, text.length).toInt();
    final prefix = snippetStart > 0 ? '...' : '';
    final suffix = snippetEnd < text.length ? '...' : '';
    return '$prefix${text.substring(snippetStart, snippetEnd)}$suffix';
  }
}
