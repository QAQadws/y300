import 'package:y300/features/comic/domain/models/comic_models.dart';

/// 阶段1使用的临时仓库接口，后续阶段可替换为本地数据库实现。
abstract class ComicRepository {
  Future<bool> isInShelf({required String comicId});

  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  });
}

class InMemoryComicRepository implements ComicRepository {
  final Set<String> _comicIds = <String>{};

  @override
  Future<bool> isInShelf({required String comicId}) async {
    return _comicIds.contains(comicId);
  }

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {
    _comicIds.add(comicId);
  }
}
