import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  const resolver = ForumReferenceResolver();

  test('malformed unrelated query values do not hide a stable thread id', () {
    const source =
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596&highlight=%D2%B2%CE%DE';

    expect(resolver.extractTid(source), '524596');
    expect(
      resolver.normalizeHref(source),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596',
    );
  });

  test('pretty thread normalization removes query and fragment', () {
    expect(
      resolver.normalizeHref(
        'https://bbs.yamibo.com/thread-100-1-1.html?from=foo#pid1',
      ),
      'https://bbs.yamibo.com/thread-100-1-1.html',
    );
  });

  test('a tid on another forum action is not treated as a thread URL', () {
    const source =
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&tid=573440';

    expect(resolver.extractTid(source), isNull);
    expect(resolver.isSupportedThreadUrl(source), isFalse);
  });

  test('cross-site references fail closed', () {
    const source = 'https://example.com/forum.php?mod=viewthread&tid=573440';

    expect(resolver.resolveSameSite(source), isNull);
    expect(resolver.extractTid(source), isNull);
  });
}
