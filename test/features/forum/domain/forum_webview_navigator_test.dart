import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_thread_link_router.dart';

void main() {
  final navigator = DefaultForumWebViewNavigator();
  final threadLinkRouter = ForumWebViewThreadLinkRouter(navigator: navigator);

  test('classify recognizes forum home', () {
    expect(
      navigator.classify(
        Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
      ),
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
    expect(navigator.extractSearchScope(uri), ForumWebViewSearchScope.curForum);
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

  test('classify keeps managed profile page under other policy', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&uid=100&do=profile&mycenter=1&mobile=2',
    );

    expect(navigator.isManagedSite(uri), isTrue);
    expect(navigator.classify(uri), ForumWebViewPageKind.other);
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

  test('thread link router normalizes viewthread mobile url with fragment', () {
    final result = threadLinkRouter.resolve(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573279&page=2#pid41575705',
    );

    expect(result.kind, ForumWebViewThreadLinkKind.threadPost);
    expect(result.tid, '573279');
    expect(result.pid, '41575705');
    expect(result.page, 2);
    expect(
      result.normalizedUri.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573279&page=2&mobile=2#pid41575705',
    );
  });

  test('thread link router parses escaped findpost redirect', () {
    final result = threadLinkRouter.resolve(
      'forum.php?mod=redirect&amp;goto=findpost&amp;ptid=570388&amp;pid=41575705&amp;mobile=2',
    );

    expect(result.kind, ForumWebViewThreadLinkKind.findPostRedirect);
    expect(result.tid, '570388');
    expect(result.pid, '41575705');
    expect(
      result.normalizedUri.toString(),
      'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=570388&pid=41575705&mobile=2',
    );
  });

  test('thread link router recognizes empty findpost redirect', () {
    final result = threadLinkRouter.resolve(
      'forum.php?mod=redirect&goto=findpost&ptid=570388&pid=',
    );

    expect(result.kind, ForumWebViewThreadLinkKind.emptyFindPostRedirect);
    expect(result.tid, '570388');
    expect(result.pid, isNull);
    expect(
      result.normalizedUri.toString(),
      'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=570388&mobile=2',
    );
  });

  test('thread link router adds mobile to managed non-thread urls only', () {
    final managed = threadLinkRouter.resolve(
      'https://bbs.yamibo.com/home.php?mod=space&uid=100',
    );
    final external = threadLinkRouter.resolve('https://example.com/thread/1');

    expect(managed.kind, ForumWebViewThreadLinkKind.none);
    expect(
      managed.normalizedUri.toString(),
      'https://bbs.yamibo.com/home.php?mod=space&uid=100&mobile=2',
    );
    expect(external.normalizedUri.toString(), 'https://example.com/thread/1');
  });
}
