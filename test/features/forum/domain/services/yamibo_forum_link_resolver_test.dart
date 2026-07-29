import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';

void main() {
  group('YamiboForumLinkResolver', () {
    const resolver = YamiboForumLinkResolver();

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
