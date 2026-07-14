import 'package:characters/characters.dart';

abstract interface class NovelChapterTitlePolicy {
  String buildTitle({
    required String normalizedPlainText,
    required int orderIndex,
    required String pid,
  });
}

class FirstMeaningfulSentenceNovelChapterTitlePolicy
    implements NovelChapterTitlePolicy {
  const FirstMeaningfulSentenceNovelChapterTitlePolicy({
    this.maxGraphemeCount = 36,
  });

  final int maxGraphemeCount;

  static final RegExp _standaloneMetadataMarker = RegExp(
    r'^[\[【（(]?\s*(?:简介|簡介|目录|目錄)\s*[\]】）)]?[：:]?$',
  );
  static final RegExp _leadingEditNotice = RegExp(
    r'^(?:本帖最后由|本帖最後由).+?(?:编辑|編輯)\s*',
  );
  static final RegExp _sentenceEnd = RegExp(
    r'^(.*?(?:……|…{2,}|\.{3,}|[。！？!?；;.])[”’」』】》]*)',
    dotAll: true,
  );

  @override
  String buildTitle({
    required String normalizedPlainText,
    required int orderIndex,
    required String pid,
  }) {
    final meaningful = _firstMeaningfulLine(normalizedPlainText);
    if (meaningful == null) {
      return '第 ${orderIndex + 1} 章';
    }

    final sentence =
        _sentenceEnd.firstMatch(meaningful)?.group(1) ?? meaningful;
    final normalizedSentence = _collapseWhitespace(sentence);
    if (normalizedSentence.isEmpty) {
      return '第 ${orderIndex + 1} 章';
    }
    return _truncate(normalizedSentence);
  }

  String? _firstMeaningfulLine(String source) {
    final normalized = source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\r\n|\r'), '\n');
    for (final rawLine in normalized.split('\n')) {
      final line = _collapseWhitespace(
        rawLine.replaceFirst(_leadingEditNotice, ''),
      );
      if (line.isEmpty || _standaloneMetadataMarker.hasMatch(line)) {
        continue;
      }
      return line;
    }
    return null;
  }

  String _truncate(String value) {
    if (maxGraphemeCount <= 0) {
      return '';
    }
    final graphemes = value.characters;
    if (graphemes.length <= maxGraphemeCount) {
      return value;
    }
    if (maxGraphemeCount == 1) {
      return '…';
    }
    return '${graphemes.take(maxGraphemeCount - 1)}…';
  }

  String _collapseWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
