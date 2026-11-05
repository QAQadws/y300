import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_bookmark_range.dart';

void main() {
  const family = '👩‍👩‍👧‍👦';
  const text = '前$family後';
  const document = NovelReaderDocument(
    episodeId: 'chapter',
    rawHtmlHash: 'hash',
    body: RichDocument(
      blocks: [
        RichTextBlock(
          anchorId: 'node-0',
          runs: [RichRun(text: text)],
        ),
      ],
    ),
    plainText: text,
    wordCount: 9,
  );
  final anchor = NovelReaderTextAnchor(
    episodeId: document.episodeId,
    nodeId: 'node-0',
    formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
    textIdentity: NovelReaderAnchorFormat.textIdentity(text),
    textOffset: 4,
  );

  test('a saved point resolves to a complete grapheme without changing it', () {
    final range = resolveNovelReaderBookmarkRange(document, anchor)!;
    expect(range.start.textOffset, 1);
    expect(range.endTextOffset, 1 + family.runes.length);
    expect(range.start.textIdentity, anchor.textIdentity);
    expect(anchor.textOffset, 4);
  });

  test('unknown and changed positions never produce a highlight range', () {
    for (final unknown in [
      anchor.copyWith(episodeId: 'other'),
      anchor.copyWith(nodeId: 'node-1'),
      anchor.copyWith(textIdentity: NovelReaderAnchorFormat.textIdentity('前文')),
      anchor.copyWith(formatVersion: NovelReaderAnchorFormat.legacyUnknown),
      anchor.copyWith(formatVersion: 2),
      anchor.copyWith(textOffset: -1),
      anchor.copyWith(textOffset: text.runes.length),
    ]) {
      expect(resolveNovelReaderBookmarkRange(document, unknown), isNull);
    }
  });
}
