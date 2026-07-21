import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_block_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_block_inspectors.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

abstract interface class NovelReaderComplexBlockMeasurer {
  Future<NovelReaderPaginationMeasureResult> measure({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  });
}

final class NovelReaderSessionComplexBlockMeasurer
    implements NovelReaderComplexBlockMeasurer {
  const NovelReaderSessionComplexBlockMeasurer(this.session);

  final NovelReaderPaginationMeasureSession session;

  @override
  Future<NovelReaderPaginationMeasureResult> measure({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    return session.measure(
      NovelReaderPaginationMeasureRequest(
        html: atom.atom.html,
        chapter: chapter,
        key: key,
        atomId: atom.atom.atomId,
        startOffset: 0,
        endOffset: atom.atom.textLength,
      ),
    );
  }
}

final class NovelReaderComplexBlockPaginationEngine {
  const NovelReaderComplexBlockPaginationEngine({
    this.rubyAdapter = const NovelReaderRubyPaginationAdapter(),
    this.collapseAdapter = const NovelReaderCollapsePaginationAdapter(),
    this.tableAdapter = const NovelReaderTablePaginationAdapter(),
  });

  final NovelReaderRubyPaginationAdapter rubyAdapter;
  final NovelReaderCollapsePaginationAdapter collapseAdapter;
  final NovelReaderTablePaginationAdapter tableAdapter;

  Future<NovelReaderComplexBlockPage> paginate({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderComplexBlockMeasurer measurer,
  }) async {
    if (atom.route == NovelReaderPaginationRoute.safeText ||
        atom.route == NovelReaderPaginationRoute.isolatedImage) {
      throw ArgumentError.value(
        atom.route,
        'atom',
        'Complex block engine accepts complex renderer routes only.',
      );
    }
    late final NovelReaderPaginationMeasureResult measurement;
    var measurementTimedOut = false;
    try {
      measurement = await measurer.measure(
        atom: atom,
        chapter: chapter,
        key: key,
      );
    } on NovelReaderPaginationException catch (error) {
      if (error.code != 'measurementTimeout') {
        rethrow;
      }
      measurementTimedOut = true;
      measurement = NovelReaderPaginationMeasureResult(
        height: key.viewportHeightPx + 1.0,
      );
    }
    if (!measurement.height.isFinite || measurement.height < 0) {
      throw const NovelReaderPaginationException(
        code: 'invalidComplexBlockMeasurement',
        message: 'Complex HTML renderer returned an invalid block height.',
      );
    }
    return NovelReaderComplexBlockPage(
      html: atom.atom.html,
      startAnchor: atom.atom.startAnchor,
      endAnchor: atom.atom.endAnchor,
      metrics: NovelReaderComplexBlockMetrics(
        height: measurement.height,
        route: atom.route,
        isOversized: measurement.height > key.viewportHeightPx,
        requiresInnerScroll:
            atom.route == NovelReaderPaginationRoute.collapseBlock ||
            measurement.height > key.viewportHeightPx,
        measurementCacheHit: measurement.fromCache,
        frameWaitCount: measurement.frameWaitCount,
        measurementTimedOut: measurementTimedOut,
        ruby: atom.route == NovelReaderPaginationRoute.rubyInline
            ? rubyAdapter.inspect(atom.atom.html)
            : null,
        collapse: atom.route == NovelReaderPaginationRoute.collapseBlock
            ? collapseAdapter.inspect(atom.atom.html)
            : null,
        table: atom.route == NovelReaderPaginationRoute.tableBlock
            ? tableAdapter.inspect(atom.atom.html)
            : null,
      ),
    );
  }
}
