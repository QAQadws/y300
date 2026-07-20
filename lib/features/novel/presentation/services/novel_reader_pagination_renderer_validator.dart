import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

final class NovelReaderRendererValidationResult {
  const NovelReaderRendererValidationResult({
    required this.actualHeight,
    required this.availableHeight,
    required this.measurementCacheHit,
    required this.frameWaitCount,
  });

  final double actualHeight;
  final double availableHeight;
  final bool measurementCacheHit;
  final int frameWaitCount;

  bool get matches => actualHeight <= availableHeight + 0.5;
}

abstract interface class NovelReaderPaginationRendererValidator {
  Future<NovelReaderRendererValidationResult> validate({
    required String html,
    required String atomId,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required double availableHeight,
  });
}

final class NovelReaderSessionPaginationRendererValidator
    implements NovelReaderPaginationRendererValidator {
  const NovelReaderSessionPaginationRendererValidator(this.session);

  final NovelReaderPaginationMeasureSession session;

  @override
  Future<NovelReaderRendererValidationResult> validate({
    required String html,
    required String atomId,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required double availableHeight,
  }) async {
    final measured = await session.measure(
      NovelReaderPaginationMeasureRequest(
        html: html,
        chapter: chapter,
        key: key,
        atomId: '$atomId:validation',
      ),
    );
    return NovelReaderRendererValidationResult(
      actualHeight: measured.height,
      availableHeight: availableHeight,
      measurementCacheHit: measured.fromCache,
      frameWaitCount: measured.frameWaitCount,
    );
  }
}

final class NovelReaderPaginationValidationPolicy {
  const NovelReaderPaginationValidationPolicy({this.interval = 16})
    : assert(interval > 0);

  final int interval;

  bool shouldValidate({
    required int safePageOrdinal,
    required bool hasRiskStyle,
  }) {
    return safePageOrdinal == 0 ||
        hasRiskStyle ||
        safePageOrdinal % interval == 0;
  }
}
