import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';

void main() {
  test('FavoriteThreadsPage.fromVariables parses count, perpage and list', () {
    final page = FavoriteThreadsPage.fromVariables(
      <String, Object?>{
        'count': '21',
        'perpage': '20',
        'list': <Map<String, Object?>>[
          <String, Object?>{
            'favid': 'f1',
            'id': '100',
            'title': '收藏帖',
            'description': '简介',
            'author': '作者A',
            'replies': '3',
            'url': 'thread-100-1-1.html',
            'dateline': '1767225600',
          },
        ],
      },
      page: 1,
    );

    expect(page.page, 1);
    expect(page.perPage, 20);
    expect(page.totalCount, 21);
    expect(page.hasMore, isTrue);
    expect(page.items.single.tid, '100');
    expect(page.items.single.replies, 3);
  });
}
