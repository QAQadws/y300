import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

abstract interface class NovelReaderSupplementalHydrationService {
  Future<List<NovelReaderBookmark>> loadBookmarks({required String novelId});

  Future<NovelItem?> loadNovel({required String novelId});
}

class DefaultNovelReaderSupplementalHydrationService
    implements NovelReaderSupplementalHydrationService {
  const DefaultNovelReaderSupplementalHydrationService({
    required NovelRepository repository,
  }) : _repository = repository;

  final NovelRepository _repository;

  @override
  Future<List<NovelReaderBookmark>> loadBookmarks({required String novelId}) {
    return _repository.listReaderBookmarks(novelId: novelId);
  }

  @override
  Future<NovelItem?> loadNovel({required String novelId}) async {
    try {
      return await _repository.getDetail(novelId: novelId);
    } catch (_) {
      return null;
    }
  }
}
