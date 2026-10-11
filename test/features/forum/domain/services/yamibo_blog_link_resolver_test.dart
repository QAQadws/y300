import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  const resolver = YamiboForumLinkResolver();
  const detail = 'home.php?mod=space&uid=101&do=blog&id=11';

  for (final origin in [
    'https://bbs.yamibo.com',
    'http://bbs.yamibo.com',
    'https://bbs.yamibo.com:443',
    'http://bbs.yamibo.com:80',
  ]) {
    test('locally proven blog details share native routing: $origin', () {
      final url = '$origin/$detail';
      final destination = resolver.resolveBrowsable(url)!;
      expect(destination.kind, YamiboForumLinkKind.blogDetail);
      expect(destination.uri.toString(), Uri.parse(url).toString());
      expect(
        destination.blogDetail!.query,
        const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'),
      );
      expect(destination.blogDetail!.focusComments, isFalse);
      expect(
        resolver.resolveBrowsingIdentity(url)?.kind,
        YamiboForumLinkKind.blogDetail,
      );
    });
  }

  test(
    'all complete comment targets retain page, identity and entry intent',
    () {
      for (final (suffix, page, commentId, last, focus) in [
        ('&page=3', 3, null, false, false),
        ('&page=1&cid=31', 1, '31', false, true),
        ('#comment_31_li', 1, '31', false, true),
        ('&goto=last', 1, null, true, true),
        ('&page=3#comment', 3, null, false, true),
        ('&page=3#quickcommentform_11', 3, null, false, true),
      ]) {
        final destination = resolver.resolveBrowsable('$detail$suffix')!;
        expect(destination.kind, YamiboForumLinkKind.blogDetail);
        final reference = destination.blogDetail!;
        expect(reference.query.page, page);
        expect(reference.query.commentId, commentId);
        expect(reference.query.lastCommentPage, last);
        expect(reference.focusComments, focus);
      }
    },
  );

  test('blog resolution does not read the viewer or acquire remote state', () {
    final destination = resolver.resolveForViewer(
      detail,
      readViewerUserId: () => throw StateError('unexpected account lookup'),
    );
    expect(destination?.kind, YamiboForumLinkKind.blogDetail);
  });

  for (final suffix in [
    '&unknown=1',
    '&view=me',
    '&cid=0',
    '&cid=31&goto=last',
    '&page=3&cid=31',
    '&page=3&goto=last',
    '&page=3#comment_31',
    '&page=3#comment_31_li',
    '&cid=31#comment_32',
    '&goto=other',
    '&page=0',
    '&page=01',
    '&uid=202',
    '&%75id=202',
    '&id=12',
    '&modblogkey=secret',
    '&op=delete',
    '&formhash=secret',
    '#unknown',
    '#quickcommentform_12',
  ]) {
    test(
      'unsupported detail never gains proof by removing fields: $suffix',
      () {
        final url = 'https://bbs.yamibo.com/$detail$suffix';
        final destination = resolver.resolve(url)!;
        expect(destination.kind, YamiboForumLinkKind.managedWebView);
        expect(destination.uri.toString(), Uri.parse(url).toString());
        expect(resolver.resolveBrowsable(url), isNull);
        expect(resolver.resolveBrowsingIdentity(url), isNull);
      },
    );
  }

  for (final reference in [
    'home.php?mod=space&uid=101&do=blog&view=all',
    'home.php?mod=space&uid=101&do=blog&view=me',
    'home.php?mod=space&uid=101&do=profile',
    'home.php?mod=space&do=blog&id=11',
    'home.php?mod=space&uid=101&do=blog&id=0',
    'home.php?mod=spacecp&ac=blog&blogid=11&op=edit',
    'https://user@bbs.yamibo.com/$detail',
    'https://bbs.yamibo.com:8443/$detail',
    'https://bbs.yamibo.com.evil.test/$detail',
    'https://elsewhere.test/$detail',
  ]) {
    test(
      'unrelated or unsafe blog URL is not a conditional target: $reference',
      () {
        expect(resolver.resolveBrowsable(reference), isNull);
        expect(resolver.resolveBrowsingIdentity(reference), isNull);
      },
    );
  }
}
