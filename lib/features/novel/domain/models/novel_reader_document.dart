import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

export 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

/// Lightweight tap payload for a novel reader link. The reader opens an in-app
/// thread when [tid] is present, otherwise falls back to launching [url].
/// Derived from a [RichRun] at tap time; kept as its own type so the page-level
/// link handler does not depend on render internals.
class NovelReaderLink {
  const NovelReaderLink({required this.url, required this.text, this.tid});

  final String url;
  final String text;
  final String? tid;
}

/// A parsed novel chapter: the shared [RichDocument] body plus novel-only
/// metadata (episode identity, source hash, plain text and word count used by
/// pagination, search and progress). The block tree itself is the canonical
/// reader_shared model — see plan §6.
class NovelReaderDocument {
  const NovelReaderDocument({
    required this.episodeId,
    required this.rawHtmlHash,
    required this.body,
    required this.plainText,
    required this.wordCount,
  });

  final String episodeId;
  final String rawHtmlHash;
  final RichDocument body;
  final String plainText;
  final int wordCount;

  /// Block tree in document order.
  List<RichBlock> get blocks => body.blocks;
}
