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
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&fid=55&mobile=2',
    );
    expect(navigator.classify(uri), ForumWebViewPageKind.threadDetail);
    expect(navigator.extractTid(uri), '100');
    expect(navigator.extractFid(uri), '55');
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
}
