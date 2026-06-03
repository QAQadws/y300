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
    expect(
      navigator.classify(
        Uri.parse('https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2'),
      ),
      ForumWebViewPageKind.forumDisplay,
    );
  });

  test('classify recognizes thread detail', () {
    expect(
      navigator.classify(
        Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2'),
      ),
      ForumWebViewPageKind.threadDetail,
    );
  });

  test('classify recognizes forum search', () {
    expect(
      navigator.classify(
        Uri.parse('https://bbs.yamibo.com/search.php?mod=forum&mobile=2'),
      ),
      ForumWebViewPageKind.search,
    );
  });

  test('classify returns other for unmanaged site', () {
    expect(
      navigator.classify(Uri.parse('https://example.com/index.php?mobile=2')),
      ForumWebViewPageKind.other,
    );
  });

  test('resolve maps relative url to managed site', () {
    expect(
      navigator.resolve('forum.php?mod=forumdisplay&fid=30&mobile=2').toString(),
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
    );
  });
}
