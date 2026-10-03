import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';

void main() {
  group('YamiboForumLinkResolver', () {
    const resolver = YamiboForumLinkResolver();

    test(
      'viewer lookup stays lazy for owner-independent or unsupported links',
      () {
        for (final reference in [
          '',
          'https://example.com/home.php?mod=space&do=friend&uid=101',
          'forum.php?mod=forumdisplay&fid=42',
          'thread-572514-4-1.html',
          'home.php?mod=space&do=profile&uid=101',
          'home.php?mod=space&do=notice',
          'home.php?mod=space&do=friend&mobile=2',
          'home.php?mod=space&do=friend&view=online&type=member',
          'home.php?mod=space&do=friend&view=visitor',
          'home.php?mod=space&do=friend&view=trace',
          'home.php?mod=space&do=friend&uid=101&view=online',
          'home.php?mod=space&do=friend&uid=101&gid=2',
          'home.php?mod=space&do=friend&uid=101&formhash=proof',
          'home.php?mod=space&do=friend&uid=101&uid=101',
          'home.php?mod=space&do=friend&uid=0',
          'https://bbs.yamibo.com:8443/home.php?mod=space&do=friend&uid=101',
        ]) {
          final candidate = resolver.resolve(reference);
          final destination = resolver.resolveForViewer(
            reference,
            readViewerUserId: () =>
                throw StateError('Unexpected viewer lookup'),
          );
          expect(destination?.kind, candidate?.kind, reason: reference);
          expect(destination?.friendScope, candidate?.friendScope);
          expect(destination?.page, candidate?.page);
        }
      },
    );

    test('eligible explicit friend owners read the verified viewer once', () {
      const reference =
          'home.php?mod=space&do=friend&uid=101&view=visitor&page=3';
      for (final viewer in ['101', '102', null]) {
        var lookups = 0;
        final destination = resolver.resolveForViewer(
          reference,
          readViewerUserId: () {
            lookups++;
            return viewer;
          },
        );
        expect(lookups, 1, reason: 'viewer=$viewer');
        expect(
          destination?.kind,
          viewer == '101'
              ? YamiboForumLinkKind.friendFeed
              : YamiboForumLinkKind.managedWebView,
        );
        if (viewer == '101') {
          expect(destination?.friendScope, ForumFriendFeedScope.visitors);
          expect(destination?.userId, '101');
          expect(destination?.page, 3);
        }
      }
    });

    test(
      'lazy lookup preserves the owner-dependent thread directory rules',
      () {
        for (final reference in [
          'home.php?mod=space&do=thread&uid=101',
          'home.php?mod=space&do=thread&uid=102',
          'home.php?mod=space&do=thread&uid=101&view=me',
          'home.php?mod=space&do=thread&view=me&type=reply&page=2',
        ]) {
          var lookups = 0;
          final destination = resolver.resolveForViewer(
            reference,
            readViewerUserId: () {
              lookups++;
              return '101';
            },
          );
          final expected = resolver.resolve(reference, viewerUserId: '101');
          expect(lookups, 1, reason: reference);
          expect(destination?.kind, expected?.kind, reason: reference);
          expect(destination?.userId, expected?.userId);
          expect(destination?.userThreadType, expected?.userThreadType);
          expect(destination?.page, expected?.page);
        }
      },
    );

    test('resolves the default friend feed including guest entry', () {
      for (final reference in [
        'https://bbs.yamibo.com/home.php?mod=space&do=friend&mobile=2',
        'home.php?mod=space&do=friend',
        '/home.php?mod=space&amp;do=friend&amp;view=me',
        '//bbs.yamibo.com/home.php?mod=space&do=friend&view=',
        'http://bbs.yamibo.com/home.php?mod=space&do=friend&mobile=no',
      ]) {
        final destination = resolver.resolve(reference);
        expect(
          destination?.kind,
          YamiboForumLinkKind.friendFeed,
          reason: reference,
        );
        expect(destination?.friendScope, ForumFriendFeedScope.friends);
        expect(destination?.userId, isNull);
        expect(destination?.page, 1);
      }
    });

    test('friend links preserve the supported tab and initial page', () {
      for (final entry in {
        'view=me': ForumFriendFeedScope.friends,
        'view=online&type=member': ForumFriendFeedScope.online,
        'view=visitor': ForumFriendFeedScope.visitors,
        'view=trace': ForumFriendFeedScope.footprints,
      }.entries) {
        final destination = resolver.resolve(
          'home.php?mod=space&do=friend&uid=101&${entry.key}&page=3&order=dateline&mobile=2',
          viewerUserId: '101',
        );
        expect(destination?.kind, YamiboForumLinkKind.friendFeed);
        expect(destination?.friendScope, entry.value);
        expect(destination?.userId, '101');
        expect(destination?.page, 3);
      }
    });

    test('explicit friend owners require the same verified viewer', () {
      const reference = 'home.php?mod=space&do=friend&uid=101&view=me';
      for (final viewer in [null, '', '102']) {
        expect(
          resolver.resolve(reference, viewerUserId: viewer)?.kind,
          YamiboForumLinkKind.managedWebView,
          reason: 'viewer=$viewer',
        );
      }
      expect(
        resolver.resolve(reference, viewerUserId: '101')?.kind,
        YamiboForumLinkKind.friendFeed,
      );
      // The default view is still the viewer's own friend list.
      expect(
        resolver
            .resolve(
              'home.php?mod=space&do=friend&uid=101',
              viewerUserId: '101',
            )
            ?.kind,
        YamiboForumLinkKind.friendFeed,
      );
    });

    test('unsupported friend filters and commands remain browser routes', () {
      for (final query in [
        'view=online',
        'view=online&type=',
        'view=online&type=friend',
        'view=online&type=all',
        'view=online&type=near',
        'view=blacklist',
        'view=all',
        'view=we',
        'view=recommend',
        'type=member',
        'view=visitor&type=member',
        'view=trace&type=member',
        'order=hot',
        'gid=2',
        'searchkey=query',
        'username=someone',
        'from=notice',
        'op=ignore',
        'ac=friend',
        'action=delete',
        'friendsubmit=1',
        'formhash=proof',
        'uid=',
        'uid=0',
        'uid=-1',
        'uid=not-a-user',
        'uid=102',
        'page=',
        'page=0',
        'page=-1',
        'page=bad',
        'page=1.5',
        'page=99999999999999999999999999999999',
        'page=1&page=2',
        'view=me&view=visitor',
        'uid=101&uid=101',
        'mobile=2&mobile=2',
        'mod=space',
        'do=friend',
      ]) {
        expect(
          resolver
              .resolve(
                'home.php?mod=space&do=friend&$query',
                viewerUserId: '101',
              )
              ?.kind,
          YamiboForumLinkKind.managedWebView,
          reason: query,
        );
      }
      expect(
        resolver
            .resolve('home.php?mod=spacecp&ac=friend&op=ignore&uid=101')
            ?.kind,
        YamiboForumLinkKind.managedWebView,
      );
      expect(
        resolver.resolve('home.php?mod=space&do=friend#request')?.kind,
        YamiboForumLinkKind.managedWebView,
      );
    });

    test('friend links reject external or ambiguous source origins', () {
      for (final origin in [
        'https://example.com',
        'https://bbs.yamibo.com.example.com',
        'https://bbs.yamibo.com:8443',
        'http://bbs.yamibo.com:443',
        'https://someone@bbs.yamibo.com',
        'ftp://bbs.yamibo.com',
      ]) {
        expect(
          resolver.resolve('$origin/home.php?mod=space&do=friend')?.kind,
          isNot(YamiboForumLinkKind.friendFeed),
          reason: origin,
        );
      }
      expect(
        resolver
            .resolve('https://bbs.yamibo.com:443/home.php?mod=space&do=friend')
            ?.kind,
        YamiboForumLinkKind.friendFeed,
      );
    });

    test('resolves the mobile target-user URL without a view parameter', () {
      final destination = resolver.resolve(
        'https://bbs.yamibo.com/home.php?mod=space&uid=260328&do=thread&mobile=2',
      );
      expect(destination?.kind, YamiboForumLinkKind.userThreadDirectory);
      expect(destination?.userId, '260328');
      expect(destination?.userThreadType, UserThreadDirectoryType.threads);
      expect(destination?.page, 1);
    });

    test('reply references retain target, tab and page across URL forms', () {
      for (final prefix in ['', '/', 'https://bbs.yamibo.com/']) {
        final destination = resolver.resolve(
          '${prefix}home.php?mod=space&amp;uid=260328&amp;do=thread&amp;view=me&amp;type=reply&amp;page=3&amp;order=dateline',
        );
        expect(destination?.kind, YamiboForumLinkKind.userThreadDirectory);
        expect(destination?.userId, '260328');
        expect(destination?.userThreadType, UserThreadDirectoryType.replies);
        expect(destination?.page, 3);
      }
    });

    test('own-space omitted view preserves the source friends view', () {
      final omitted = resolver.resolve(
        'home.php?mod=space&uid=101&do=thread&mobile=2',
        viewerUserId: '101',
      );
      expect(omitted?.kind, YamiboForumLinkKind.managedWebView);
      final personal = resolver.resolve(
        'home.php?mod=space&uid=101&do=thread&view=me&mobile=2',
        viewerUserId: '101',
      );
      expect(personal?.kind, YamiboForumLinkKind.userThreadDirectory);
      final other = resolver.resolve(
        'home.php?mod=space&uid=260328&do=thread&mobile=2',
        viewerUserId: '101',
      );
      expect(other?.kind, YamiboForumLinkKind.userThreadDirectory);
    });

    test('an explicit personal view can use the verified current user', () {
      final destination = resolver.resolve(
        'home.php?mod=space&do=thread&view=me&type=thread',
      );
      expect(destination?.kind, YamiboForumLinkKind.userThreadDirectory);
      expect(destination?.userId, isNull);
      expect(destination?.userThreadType, UserThreadDirectoryType.threads);
    });

    test('unsupported directory semantics retain source browser behavior', () {
      for (final query in [
        'uid=260328&view=all',
        'uid=260328&view=we',
        'uid=260328&type=postcomment',
        'uid=260328&type=unknown',
        'uid=260328&order=lastpost',
        'uid=260328&searchkey=query',
        'uid=260328&fuid=3',
        'uid=260328&page=0',
        'uid=260328&page=bad',
        'uid=0',
        'uid=-1',
        'uid=not-a-user',
        'uid=260328&uid=123',
        'view=all',
        '',
      ]) {
        expect(
          resolver.resolve('home.php?mod=space&do=thread&$query')?.kind,
          YamiboForumLinkKind.managedWebView,
          reason: query,
        );
      }
    });

    test(
      'other origins and ambiguous origin credentials never map natively',
      () {
        for (final origin in [
          'https://example.com',
          'https://bbs.yamibo.com.example.com',
          'https://bbs.yamibo.com:8443',
          'https://someone@bbs.yamibo.com',
          'ftp://bbs.yamibo.com',
        ]) {
          expect(
            resolver
                .resolve('$origin/home.php?mod=space&uid=260328&do=thread')
                ?.kind,
            isNot(YamiboForumLinkKind.userThreadDirectory),
            reason: origin,
          );
        }
      },
    );

    test('preserves page numbers for native thread and tag entry points', () {
      expect(resolver.resolve('thread-572514-4-1.html')?.page, 4);
      expect(
        resolver.resolve('forum.php?mod=viewthread&tid=572514&page=3')?.page,
        3,
      );
      expect(resolver.resolve('misc.php?mod=tag&id=28&page=2')?.page, 2);
      expect(
        resolver.resolve('forum.php?mod=viewthread&tid=572514&page=-2')?.page,
        isNull,
      );
    });

    test('resolves pretty thread links as native thread destinations', () {
      final destination = resolver.resolve(
        'https://bbs.yamibo.com/thread-572514-1-1.html',
      );

      expect(destination?.kind, YamiboForumLinkKind.thread);
      expect(destination?.tid, '572514');
    });

    test('resolves viewthread hash pid links as native post targets', () {
      final destination = resolver.resolve(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572057&page=3&extra=#pid41560047',
      );

      expect(destination?.kind, YamiboForumLinkKind.threadPost);
      expect(destination?.tid, '572057');
      expect(destination?.pid, '41560047');
      expect(destination?.page, 3);
    });

    test('resolves findpost redirect links as native post targets', () {
      final destination = resolver.resolve(
        'https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=572057&amp;pid=41554030&amp;fromuid=420637',
      );

      expect(destination?.kind, YamiboForumLinkKind.threadPost);
      expect(destination?.tid, '572057');
      expect(destination?.pid, '41554030');
      expect(destination?.page, isNull);
    });

    test('ignores optional fromuid when resolving a generated floor link', () {
      final destination = resolver.resolve(
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=573908&pid=41585107&fromuid=597454',
      );

      expect(destination?.kind, YamiboForumLinkKind.threadPost);
      expect(destination?.tid, '573908');
      expect(destination?.pid, '41585107');
      expect(destination?.page, isNull);
    });

    test('resolves tag links as normalized native tag page destinations', () {
      final destination = resolver.resolve(
        'https://bbs.yamibo.com/misc.php?mod=tag&amp;id=21920',
      );

      expect(destination?.kind, YamiboForumLinkKind.tagThreadPage);
      expect(destination?.tagId, '21920');
      expect(destination?.uri.toString(), contains('type=thread'));
      expect(destination?.uri.toString(), contains('page=1'));
    });

    test('keeps same-domain unimplemented links in managed WebView bucket', () {
      final destination = resolver.resolve(
        'https://bbs.yamibo.com/home.php?mod=space&uid=399468',
      );

      expect(destination?.kind, YamiboForumLinkKind.managedWebView);
    });

    test('classifies external links without rewriting them', () {
      final destination = resolver.resolve('https://example.com/a');

      expect(destination?.kind, YamiboForumLinkKind.external);
      expect(destination?.uri.toString(), 'https://example.com/a');
    });
  });
}
