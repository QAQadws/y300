import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';

void main() {
  group('YamiboForumLinkResolver', () {
    const resolver = YamiboForumLinkResolver();

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
