import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/services/novel_first_post_catalog_extractor.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_parser.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

import '../../test_support/novel_phase0_api_fixtures.dart';

void main() {
  group('DefaultNovelSourceMetadataParser', () {
    const parser = DefaultNovelSourceMetadataParser();
    final ingestedAt = DateTime(2026, 7, 13, 15, 30);

    test('reads only first post from the unsafe version=4 fixture', () async {
      final fixture = await NovelPhase0ApiFixture.load(
        novelPhase0FavoriteDetailV4FixturePath,
      );
      final detail = fixture.parseDetail();

      final metadata = parser.parseFirstPost(
        seed: NovelSourceSeed(
          fid: detail.fid,
          tid: detail.tid,
          typeid: detail.typeid,
          tagName: '長篇連載',
        ),
        detail: detail,
        ingestedAt: ingestedAt,
      );

      expect(metadata.novelId, 'novel:55:521519');
      expect(metadata.publisherName, 'INCSKY16');
      expect(metadata.publisherId, '406769');
      expect(metadata.firstPostPid, '40213901');
      expect(metadata.sourceIntro, '这是用于测试首楼元数据边界的脱敏简介。');
      expect(metadata.catalogEntries, hasLength(1));
      expect(metadata.catalogEntries.single.pid, '40213902');
      expect(metadata.catalogEntries.single.title, '第 1 话');
      expect(metadata.catalogEntries.single.url, contains('goto=findpost'));
      expect(metadata.coverImageUrl, isNull);
      expect(metadata.sourceApiVersion, 4);
      expect(metadata.ingestedAt, ingestedAt);
    });

    test('never reads, validates, or iterates later version=4 posts', () {
      final firstPost = _post();
      final guardedPosts = _FirstPostOnlyList(firstPost, reportedLength: 3);

      final metadata = parser.parseFirstPost(
        seed: const NovelSourceSeed(fid: '49', tid: '200'),
        detail: _detail(posts: guardedPosts),
        ingestedAt: ingestedAt,
      );

      expect(metadata.firstPostPid, '11');
      expect(guardedPosts.accessedIndexes, <int>[0]);
    });

    test('uses only the first valid ordinary first-post image as cover', () {
      final metadata = parser.parseFirstPost(
        seed: const NovelSourceSeed(fid: '49', tid: '200'),
        detail: _detail(
          posts: <ThreadPost>[
            _post(
              message: '''
                <p>简介：测试</p><p>目录</p>
                <img src="static/image/smiley.gif">
                <img src="https://cdn.example.test/cover.webp">
                <img src="https://cdn.example.test/later.jpg">
              ''',
            ),
            _post(
              pid: '12',
              number: 2,
              message: '<img src="https://cdn.example.test/wrong.jpg">',
            ),
          ],
        ),
        ingestedAt: ingestedAt,
      );

      expect(metadata.coverImageUrl, 'https://cdn.example.test/cover.webp');
    });

    test('rejects missing first post and invalid publisher id', () {
      expect(
        () => parser.parseFirstPost(
          seed: const NovelSourceSeed(fid: '49', tid: '200'),
          detail: _detail(posts: const <ThreadPost>[]),
          ingestedAt: ingestedAt,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parser.parseFirstPost(
          seed: const NovelSourceSeed(fid: '49', tid: '200'),
          detail: _detail(posts: <ThreadPost>[_post(authorId: '')]),
          ingestedAt: ingestedAt,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('NovelFirstPostCatalogExtractor', () {
    const extractor = NovelFirstPostCatalogExtractor();

    test('deduplicates same-thread findpost links without decoding noise', () {
      final entries = extractor.extract(
        threadTid: '200',
        firstPost: _post(
          message: '''
            <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=200&amp;pid=11&amp;highlight=%D2%B2">第一章</a>
            <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=200&amp;pid=11">重复第一章</a>
            <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=201&amp;pid=12">其它帖子</a>
            <a href="forum.php?mod=viewthread&amp;tid=200">普通链接</a>
          ''',
        ),
      );

      expect(entries, hasLength(1));
      expect(entries.single.position, 0);
      expect(entries.single.pid, '11');
      expect(entries.single.title, '第一章');
      expect(entries.single.url, isNot(contains('highlight')));
      expect(
        entries.single.url,
        endsWith('mod=redirect&goto=findpost&ptid=200&pid=11'),
      );
    });
  });
}

ThreadDetailData _detail({required List<ThreadPost> posts}) {
  return ThreadDetailData(
    tid: '200',
    fid: '49',
    typeid: '293',
    subject: '[原创] 测试小说',
    author: '作者',
    replies: posts.length - 1,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: posts,
  );
}

ThreadPost _post({
  String pid = '11',
  String author = '作者',
  String authorId = '99',
  String message = '<p>简介</p><p>目录</p>',
  int number = 1,
}) {
  return ThreadPost(
    pid: pid,
    author: author,
    authorId: authorId,
    message: message,
    number: number,
    isFirst: number == 1,
    dateline: '2026-07-13',
  );
}

class _FirstPostOnlyList extends ListBase<ThreadPost> {
  _FirstPostOnlyList(this.firstPost, {required this.reportedLength});

  final ThreadPost firstPost;
  final int reportedLength;
  final List<int> accessedIndexes = <int>[];

  @override
  int get length => reportedLength;

  @override
  set length(int value) => throw UnsupportedError('read-only fixture');

  @override
  ThreadPost operator [](int index) {
    accessedIndexes.add(index);
    if (index == 0) {
      return firstPost;
    }
    throw StateError('Later version=4 post was accessed: $index');
  }

  @override
  void operator []=(int index, ThreadPost value) {
    throw UnsupportedError('read-only fixture');
  }
}
