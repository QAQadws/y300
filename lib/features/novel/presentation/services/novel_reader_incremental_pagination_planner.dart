import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';

abstract interface class NovelReaderIncrementalPaginationPlanner {
  Stream<NovelReaderPaginationProgress> planIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationCancellationToken cancellationToken,
  });
}
