import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

/// 漫画仓库：封装书架数据访问，屏蔽具体存储实现。
abstract class ComicRepository {
  Future<bool> isInShelf({required String comicId});

  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  });

  Future<List<ComicShelfItem>> getShelfItems({
    String categoryId = 'default',
  });
}
