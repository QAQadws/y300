import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/presentation/comic_shelf_page.dart';

void main() {
  testWidgets('ComicShelfPage shows empty text when shelf has no data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_EmptyComicRepository()),
        ],
        child: const MaterialApp(home: ComicShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('书架还是空的，去帖子详情把喜欢的漫画加入书架吧'), findsOneWidget);
  });

  testWidgets('ComicShelfPage title overlay uses custom two-line ellipsis', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(
            _DataComicRepository(
              ComicShelfItem(
                comicId: 'yamibo:100',
                title:
                    '这是一个非常非常长的漫画标题用于验证第二行结尾使用中文省略号点点点样式并且继续延长文本长度让它在绝大多数测试设备宽度下都必然触发两行截断效果',
                author: '作者A',
                coverImageUrl: null,
                categoryId: 'default',
                addedAt: DateTime(2026, 1, 1),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: ComicShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-shelf-grid')), findsOneWidget);
    expect(find.textContaining('···'), findsOneWidget);
  });
}

class _EmptyComicRepository implements ComicRepository {
  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <ComicShelfItem>[];
  }

  @override
  Future<bool> isInShelf({required String comicId}) async {
    return false;
  }
}

class _DataComicRepository implements ComicRepository {
  _DataComicRepository(this.item);

  final ComicShelfItem item;

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async {
    return <ComicShelfItem>[item];
  }

  @override
  Future<bool> isInShelf({required String comicId}) async {
    return comicId == item.comicId;
  }
}
