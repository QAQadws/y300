import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';

/// Owns derived data for one reader owner, without retaining a measurement
/// session, context or overlay. Chapter/layout changes can reuse exact keys;
/// retiring the reader owner permanently closes all four caches.
final class NovelReaderPaginationSessionCache {
  NovelReaderPaginationSessionCache({
    NovelReaderPaginationCache? paginationCache,
    NovelReaderPaginationMeasureCache? measureCache,
    NovelReaderComplexHtmlBoundaryCache? boundaryCache,
    NovelReaderPreparedChapterCache? preparedChapterCache,
  }) : paginationCache = paginationCache ?? NovelReaderPaginationCache(),
       measureCache = measureCache ?? NovelReaderPaginationMeasureCache(),
       boundaryCache = boundaryCache ?? NovelReaderComplexHtmlBoundaryCache(),
       preparedChapterCache =
           preparedChapterCache ?? NovelReaderPreparedChapterCache();

  final NovelReaderPaginationCache paginationCache;
  final NovelReaderPaginationMeasureCache measureCache;
  final NovelReaderComplexHtmlBoundaryCache boundaryCache;
  final NovelReaderPreparedChapterCache preparedChapterCache;
  bool _closed = false;

  bool get isClosed => _closed;
  int get estimatedRetainedBytes =>
      paginationCache.estimatedRetainedBytes +
      measureCache.estimatedRetainedBytes +
      boundaryCache.estimatedRetainedBytes +
      preparedChapterCache.estimatedRetainedBytes;

  /// Clearing the owner is terminal. Individual cache.clear() remains a
  /// reusable invalidation operation for callers that still own that cache.
  void clear() => dispose();

  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    paginationCache.dispose();
    measureCache.dispose();
    boundaryCache.dispose();
    preparedChapterCache.dispose();
  }
}
