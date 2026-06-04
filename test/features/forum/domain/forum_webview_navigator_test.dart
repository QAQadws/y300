import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';

void main() {
  final navigator = DefaultForumWebViewNavigator();

  test('classify recognizes forum home', () {
    expect(
      navigator.classify(Uri.parse('https://bbs.yamibo.com/index.php?mobile=2')),
      ForumWebViewPageKind.home,
    );
  });

  test('classify recognizes forum display', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    expect(navigator.classify(uri), ForumWebViewPageKind.forumDisplay);
    expect(navigator.extractFid(uri), '55');
  });

  test('classify recognizes thread detail', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2',
    );
    expect(navigator.classify(uri), ForumWebViewPageKind.threadDetail);
    expect(navigator.extractTid(uri), '100');
    expect(navigator.extractFid(uri), isNull);
  });

  test('thread detail can also extract fid when query carries it', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&fid=55&authorid=9&ordertype=1&mobile=2',
    );
    expect(navigator.classify(uri), ForumWebViewPageKind.threadDetail);
    expect(navigator.extractTid(uri), '100');
    expect(navigator.extractFid(uri), '55');
    expect(navigator.extractAuthorId(uri), '9');
    expect(navigator.isReverseOrder(uri), isTrue);
  });

  test('classify recognizes forum search', () {
    expect(
      navigator.classify(
        Uri.parse('https://bbs.yamibo.com/search.php?mod=forum&mobile=2'),
      ),
      ForumWebViewPageKind.search,
    );
    expect(
      navigator.extractSearchScope(
        Uri.parse('https://bbs.yamibo.com/search.php?mod=forum&mobile=2'),
      ),
      ForumWebViewSearchScope.forum,
    );
  });

  test('classify recognizes curforum search and extracts search fid', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=30&mobile=2',
    );
    expect(navigator.classify(uri), ForumWebViewPageKind.search);
    expect(
      navigator.extractSearchScope(uri),
      ForumWebViewSearchScope.curForum,
    );
    expect(navigator.extractSearchFid(uri), '30');
  });

  test('classify recognizes search result url', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
    );
    expect(navigator.classify(uri), ForumWebViewPageKind.search);
    expect(navigator.extractSearchScope(uri), isNull);
  });

  test('classify returns other for unmanaged site', () {
    expect(
      navigator.classify(Uri.parse('https://example.com/index.php?mobile=2')),
      ForumWebViewPageKind.other,
    );
  });

  test('resolve maps relative url to managed site', () {
    final resolved = navigator.resolve(
      'forum.php?mod=forumdisplay&fid=30&mobile=2',
    );
    expect(
      resolved.toString(),
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
    );
    expect(navigator.classify(resolved), ForumWebViewPageKind.forumDisplay);
    expect(navigator.extractFid(resolved), '30');
  });

  test('forumSearchUri builds managed forum search url', () {
    expect(
      navigator.forumSearchUri().toString(),
      'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
    );
  });

  test('curForumSearchUri builds managed current forum search url', () {
    expect(
      navigator.curForumSearchUri(fid: '30').toString(),
      'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=30&mobile=2',
    );
  });

  test('buildNormalThreadUri removes authorid while preserving other params', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&authorid=9&extra=page%3D1&page=2&mobile=2',
    );

    expect(
      navigator.buildNormalThreadUri(uri).toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&extra=page%3D1&page=2&mobile=2',
    );
  });

  test('buildReverseOrderUri adds ordertype while preserving current params', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&extra=page%3D1&page=2&mobile=2',
    );

    expect(
      navigator.buildReverseOrderUri(uri).toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&extra=page%3D1&page=2&mobile=2&ordertype=1',
    );
  });

  test('buildNormalOrderUri removes ordertype while preserving current params', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&extra=page%3D1&page=2&ordertype=1&mobile=2',
    );

    expect(
      navigator.buildNormalOrderUri(uri).toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&extra=page%3D1&page=2&mobile=2',
    );
  });

  test('buildAuthorOnlyUri writes authorid onto the current thread url', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&extra=page%3D1&page=2&mobile=2',
    );

    expect(
      navigator.buildAuthorOnlyUri(currentUri: uri, authorId: '9').toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&extra=page%3D1&page=2&mobile=2&authorid=9',
    );
  });
}
