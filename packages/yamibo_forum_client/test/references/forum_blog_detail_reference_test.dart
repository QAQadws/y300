import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  const resolver = ForumReferenceResolver();
  const detail = 'home.php?mod=space&uid=101&do=blog&id=11';

  for (final origin in [
    'https://bbs.yamibo.com',
    'http://bbs.yamibo.com',
    'https://bbs.yamibo.com:443',
    'http://bbs.yamibo.com:80',
  ]) {
    test('standard web origin resolves blog details: $origin', () {
      final reference = resolver.resolveBlogDetailReference('$origin/$detail')!;
      expect(
        reference.query,
        const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'),
      );
      expect(reference.focusComments, isFalse);
    });
  }

  test('relative escaped detail resolves and preserves comment page', () {
    final reference = resolver.resolveBlogDetailReference(
      '${detail.replaceAll('&', '&amp;')}&amp;page=3',
    )!;
    expect(
      reference.query,
      const UserBlogDetailQuery(ownerUserId: '101', blogId: '11', page: 3),
    );
    expect(reference.focusComments, isFalse);
  });

  test('comment anchors use the complete actual detail base', () {
    for (final fragment in [
      'comment',
      'quickcommentform_11',
      'comment_31',
      'comment_31_li',
    ]) {
      final page = fragment.startsWith('comment_') ? 1 : 2;
      final reference = resolver.resolveBlogDetailReference(
        '#$fragment',
        baseUrl: 'https://bbs.yamibo.com/$detail&page=$page',
      )!;
      expect(reference.query.ownerUserId, '101');
      expect(reference.query.blogId, '11');
      expect(reference.query.page, page);
      expect(
        reference.query.commentId,
        fragment.startsWith('comment_') ? '31' : null,
      );
      expect(reference.focusComments, isTrue);
    }
  });

  test('comment selectors retain source entry intent', () {
    final comment = resolver.resolveBlogDetailReference('$detail&cid=31')!;
    expect(comment.query.commentId, '31');
    expect(comment.focusComments, isTrue);
    final last = resolver.resolveBlogDetailReference('$detail&goto=last')!;
    expect(last.query.lastCommentPage, isTrue);
    expect(last.focusComments, isTrue);
  });

  for (final value in [
    'https://elsewhere.test/$detail',
    'https://user@bbs.yamibo.com/$detail',
    'https://bbs.yamibo.com:8443/$detail',
    'http://bbs.yamibo.com:443/$detail',
    'home.php?mod=space&uid=101&do=blog&view=all',
    'home.php?mod=space&uid=101&do=profile',
    'home.php?mod=space&do=blog&id=11',
    '$detail&uid=202',
    '$detail&%75id=202',
    '$detail&page=0',
    '$detail&cid=31&goto=last',
    '$detail&page=3&cid=31',
    '$detail&page=3&goto=last',
    '$detail&page=3#comment_31',
    '$detail&page=3#comment_31_li',
    '$detail&unknown=1',
    '$detail&op=delete',
    '$detail&modblogkey=secret',
    '$detail#comment_31_bad',
    '$detail&cid=31#comment_32',
  ]) {
    test('non-detail or unrepresented reference fails closed: $value', () {
      expect(resolver.resolveBlogDetailReference(value), isNull);
    });
  }

  test('configured source boundaries remain authoritative', () {
    const other = ForumReferenceResolver(siteOrigin: 'https://example.test');
    expect(other.resolveBlogDetailReference(detail), isNotNull);
    expect(
      other.resolveBlogDetailReference('https://bbs.yamibo.com/$detail'),
      isNull,
    );
    const invalid = ForumReferenceResolver(
      siteOrigin: 'https://user@example.test',
    );
    expect(invalid.resolveBlogDetailReference(detail), isNull);
  });
}
