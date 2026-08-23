import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/services/forum_home_snapshot_codec.dart';
import 'package:y300/features/forum/domain/models/forum_directory_models.dart';

void main() {
  const codec = ForumHomeSnapshotCodec();

  test('v3 snapshot writes only the source-neutral directory schema', () {
    final encoded =
        codec.encode(
              ForumHomePayload(
                directory: const ForumDirectoryData(
                  sections: [
                    ForumDirectorySection(
                      identity: '14',
                      title: '庙堂',
                      forums: [
                        ForumDirectoryForum(
                          fid: '30',
                          title: '漫画区',
                          description: '漫画讨论',
                          todayPosts: 5,
                        ),
                      ],
                    ),
                  ],
                ),
                isLoggedIn: false,
                favoriteForums: const <FavoriteForum>[],
              ),
            )
            as Map<String, Object?>;

    expect(codec.codecVersion, 3);
    expect(codec.parserVersion, 3);
    expect(encoded, contains('directory'));
    expect(encoded, isNot(contains('forumIndex')));
    expect(encoded, isNot(contains('homeSections')));
  });

  test('v2 snapshot decodes regular sections without favorite projection', () {
    final decoded = codec.decode(<String, Object?>{
      'isLoggedIn': true,
      'forumIndex': <String, Object?>{
        'categories': <Object?>[
          <String, Object?>{
            'fid': '14',
            'name': '庙堂',
            'forums': <String>['30'],
          },
        ],
        'forums': <Object?>[
          <String, Object?>{
            'fid': '30',
            'name': '旧漫画区',
            'todayPosts': 0,
            'description': '',
            'subForums': <Object?>[],
          },
        ],
      },
      'favoriteForums': <Object?>[],
      'homeSections': <Object?>[
        <String, Object?>{
          'title': '我收藏的版块',
          'kind': 'favorite',
          'items': <Object?>[
            <String, Object?>{
              'fid': '33',
              'title': '收藏版块',
              'description': '',
              'todayPosts': 9,
            },
          ],
        },
        <String, Object?>{
          'title': '庙堂',
          'kind': 'regular',
          'items': <Object?>[
            <String, Object?>{
              'fid': '30',
              'title': '漫画区',
              'description': '漫画讨论',
              'todayPosts': null,
            },
          ],
        },
      ],
      'chromeData': <String, Object?>{},
    });

    expect(decoded.directory.sections.single.identity, '14');
    expect(decoded.directory.sections.single.forums.single.title, '漫画区');
    expect(decoded.directory.sections.single.forums.single.todayPosts, isNull);
  });
}
