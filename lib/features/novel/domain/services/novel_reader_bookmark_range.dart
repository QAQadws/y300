import 'package:characters/characters.dart';

import '../models/novel_reader_anchor_format.dart';
import '../models/novel_reader_document.dart';
import '../models/novel_reader_marks.dart';
import '../models/novel_rich_block_text.dart';

/// Resolves a saved point against the current semantic text. Rendering still
/// has to project the range and prove that its glyphs are visible.
NovelReaderTextRange? resolveNovelReaderBookmarkRange(
  NovelReaderDocument document,
  NovelReaderTextAnchor anchor,
) {
  final nodeId = anchor.nodeId;
  if (anchor.episodeId != document.episodeId ||
      nodeId == null ||
      !anchor.hasCanonicalTextOffset ||
      anchor.textOffset < 0) {
    return null;
  }
  final block = document.blocks
      .where((block) => block.anchorId == nodeId)
      .firstOrNull;
  if (block == null) return null;
  final text = block.novelPlainText;
  if (anchor.textIdentity != NovelReaderAnchorFormat.textIdentity(text)) {
    return null;
  }

  var start = 0;
  for (final grapheme in text.characters) {
    final end = start + grapheme.runes.length;
    if (anchor.textOffset < end) {
      return NovelReaderTextRange(anchor.copyWith(textOffset: start), end);
    }
    start = end;
  }
  return null;
}
