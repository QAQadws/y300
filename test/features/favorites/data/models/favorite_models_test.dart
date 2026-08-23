import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/mappers/favorite_directory_api_mappers.dart';

void main() {
  const mapper = FavoriteThreadDirectoryApiMapper();

  test('maps exact pagination and source-neutral thread fields', () {
    final page = mapper.mapVariables(<String, Object?>{
      'count': '2',
      'perpage': '1',
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
    }, requestedPage: 1);

    expect(page.pagination.currentPage, 1);
    expect(page.pagination.pageSize, 1);
    expect(page.pagination.totalItems, 2);
    expect(page.pagination.totalPages, 2);
    expect(page.pagination.hasNext, isTrue);
    expect(page.items.single.tid, '100');
    expect(page.items.single.replyCount, 3);
    expect(page.items.single.remoteFavoriteId, 'f1');
    expect(page.items.single.favoritedAt?.isUtc, isTrue);
  });

  test('keeps missing optional values and timestamp sentinel null', () {
    final page = mapper.mapVariables(<String, Object?>{
      'count': '1',
      'perpage': '20',
      'list': <Map<String, Object?>>[
        <String, Object?>{'id': '100', 'title': '收藏帖', 'dateline': '0'},
      ],
    }, requestedPage: 1);

    expect(page.items.single.replyCount, isNull);
    expect(page.items.single.favoritedAt, isNull);
  });

  test('rejects present but malformed numeric values', () {
    expect(
      () => mapper.mapVariables(<String, Object?>{
        'count': '1',
        'perpage': '20',
        'list': <Map<String, Object?>>[
          <String, Object?>{
            'id': '100',
            'title': '收藏帖',
            'replies': '3 replies',
          },
        ],
      }, requestedPage: 1),
      throwsFormatException,
    );
  });
}
