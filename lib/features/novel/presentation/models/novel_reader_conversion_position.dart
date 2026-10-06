import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';

/// A visible position in an actual display projection, scoped to this reader.
/// It is a conversion hint, never a replacement for persisted reading progress.
final class NovelReaderConversionPosition {
  const NovelReaderConversionPosition({
    required this.rawHtml,
    required this.conversionIdentity,
    required this.chapter,
    required this.anchor,
  });

  final String rawHtml;
  final String conversionIdentity;
  final NovelReaderPreparedChapter chapter;
  final NovelReaderTextAnchor anchor;
}
