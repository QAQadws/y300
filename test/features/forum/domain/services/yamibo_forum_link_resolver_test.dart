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
