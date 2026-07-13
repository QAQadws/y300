import 'package:flutter_test/flutter_test.dart';

import '../test_support/novel_phase0_api_fixtures.dart';

void main() {
  group('novel Phase 0 API fixtures', () {
    test('observed authorid response keeps default ppp=20', () async {
      final fixture = await NovelPhase0ApiFixture.load(
        novelPhase0ObservedAuthorPageFixturePath,
      );
      final detail = fixture.parseDetail();
      final requestQuery =
          fixture.metadata['requestQuery'] as Map<String, dynamic>;
      final thread = fixture.variables['thread'] as Map<String, dynamic>;

      expect(fixture.root['Version'], '1');
      expect(fixture.variables, isNot(contains('auth')));
      expect(fixture.variables, isNot(contains('formhash')));
      expect(requestQuery['authorid'], '121222');
      expect(requestQuery, isNot(contains('ppp')));
      expect(fixture.metadata['postsPerPageWasExplicit'], isFalse);
      expect(detail.tid, '564823');
      expect(detail.perPage, 20);
      expect(detail.replies, 38);
      expect(detail.views, 16107);
      expect(thread['allreplies'], '181');
      expect(thread['maxposition'], '182');
      expect(detail.posts, hasLength(20));
      expect(
        detail.posts.map((post) => post.number),
        orderedEquals(List<int>.generate(20, (index) => index + 1)),
      );
      expect(detail.posts.map((post) => post.authorId), everyElement('121222'));
      expect(detail.hasMore, isTrue);
    });

    test(
      'version=4 favorite detail keeps valid metadata in first post',
      () async {
        final fixture = await NovelPhase0ApiFixture.load(
          novelPhase0FavoriteDetailV4FixturePath,
        );
        final detail = fixture.parseDetail();

        expect(fixture.root['Version'], '4');
        expect(detail.tid, '521519');
        expect(detail.fid, '55');
        expect(detail.typeid, '295');
        expect(detail.posts, hasLength(3));
        expect(detail.posts.first.pid, '40213901');
        expect(detail.posts.first.author, 'INCSKY16');
        expect(detail.posts.first.authorId, '406769');
        expect(detail.posts.first.message, contains('脱敏简介'));
        expect(detail.posts.first.message, contains('goto=findpost'));
      },
    );

    test(
      'version=4 later post contains an unsafe legacy URL boundary',
      () async {
        final fixture = await NovelPhase0ApiFixture.load(
          novelPhase0FavoriteDetailV4FixturePath,
        );
        final detail = fixture.parseDetail();
        final unsafePids = (fixture.metadata['unsafeLaterPostPids'] as List)
            .map((value) => value.toString())
            .toSet();

        expect(unsafePids, <String>{'40213902', '40213904'});
        final unsafeMessage = detail.posts
            .singleWhere((post) => post.pid == '40213902')
            .message;
        final href = RegExp(
          r'href="([^"]+)"',
        ).firstMatch(unsafeMessage)!.group(1)!.replaceAll('&amp;', '&');

        expect(
          () => Uri.parse(href).queryParameters,
          throwsA(isA<FormatException>()),
          reason: 'A future metadata parser must never inspect later posts.',
        );
      },
    );

    test(
      'version=1 author fixtures preserve the three-page crawl contract',
      () async {
        final fixtures = <NovelPhase0ApiFixture>[];
        for (final path in novelPhase0AuthorPageFixturePaths) {
          fixtures.add(await NovelPhase0ApiFixture.load(path));
        }

        expect(
          fixtures.map((fixture) => fixture.root['Version']),
          everyElement('1'),
        );
        expect(
          fixtures.map((fixture) => fixture.variables['ppp']),
          everyElement('200'),
        );
        expect(fixtures.map((fixture) => fixture.requestedPage), <int>[
          1,
          2,
          3,
        ]);
        expect(
          fixtures.map((fixture) => fixture.metadata['originalPostCount']),
          <int>[200, 200, 23],
        );
        for (final fixture in fixtures) {
          expect(fixture.metadata['authorId'], '406769');
          expect(
            fixture.parseDetail().posts.map((post) => post.authorId),
            everyElement('406769'),
          );
        }
        expect(fixtures.map((fixture) => fixture.parseDetail().hasMore), <bool>[
          true,
          true,
          false,
        ]);
        expect(
          fixtures
              .expand((fixture) => fixture.parseDetail().posts)
              .map((post) => post.number),
          <int>[1, 200, 201, 400, 401, 423],
        );
      },
    );

    test('author-filtered page is not an ordinary thread route page', () async {
      final secondPage = await NovelPhase0ApiFixture.load(
        novelPhase0AuthorPageFixturePaths[1],
      );
      final thirdPage = await NovelPhase0ApiFixture.load(
        novelPhase0AuthorPageFixturePaths[2],
      );

      final secondRoute =
          secondPage.metadata['routeEvidence'] as Map<String, dynamic>;
      final thirdRoute =
          thirdPage.metadata['routeEvidence'] as Map<String, dynamic>;

      expect(secondRoute['pid'], '40692958');
      expect(secondRoute['authorFilteredPage'], 2);
      expect(secondRoute['ordinaryThreadPage'], 265);
      expect(thirdRoute['pid'], '41397522');
      expect(thirdRoute['authorFilteredPage'], 3);
      expect(thirdRoute['ordinaryThreadPage'], 722);
      expect(
        secondRoute['authorFilteredPage'],
        isNot(secondRoute['ordinaryThreadPage']),
      );
      expect(
        thirdRoute['authorFilteredPage'],
        isNot(thirdRoute['ordinaryThreadPage']),
      );
    });
  });
}
