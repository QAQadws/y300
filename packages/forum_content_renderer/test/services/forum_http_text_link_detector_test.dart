import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  const detector = ForumHttpTextLinkDetector();

  test(
    'preserves source URLs, query, fragment and UTF-16 occurrence ranges',
    () {
      const url =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123#pid456';
      const text = '😀分享：$url，随后 $url。';
      final result = detector.detect(text);
      expect(result.isLimited, isFalse);
      expect(result.links, hasLength(2));
      expect(result.links.map((link) => link.text), [url, url]);
      expect(result.links.first.start, text.indexOf(url));
      for (final link in result.links) {
        expect(text.substring(link.start, link.end), url);
        expect(link.uri.queryParameters['tid'], '123');
        expect(link.uri.fragment, 'pid456');
      }
    },
  );

  test('recognizes case-insensitive HTTP schemes and explicit hosts only', () {
    final result = detector.detect(
      'HTTPS://Example.COM/a http://127.0.0.1:8080/a '
      'https://[::1]/a http://localhost/a www.example.com '
      '/forum.php https:///path https:// https://bbs. https://bbs '
      'javascript:https://example.com file://example.com '
      'prefixhttps://example.com https://-bad.example/a '
      'https://good.bad-/a https://example.com:bad/a '
      'https://example.com/%xy https://example.com\\evil',
    );
    expect(result.links.map((link) => link.text), [
      'HTTPS://Example.COM/a',
      'http://127.0.0.1:8080/a',
      'https://[::1]/a',
      'http://localhost/a',
    ]);
  });

  test('trims prose punctuation but keeps balanced URL parentheses', () {
    final result = detector.detect(
      '（https://example.com/a(b)?next=x%20y#part） '
      '(https://example.com/a(b)). '
      '[https://example.com/abc], '
      '“https://example.com/a?q=1,2。” '
      'https://example.com/a,https://example.net/b',
    );
    expect(result.links.map((link) => link.text), [
      'https://example.com/a(b)?next=x%20y#part',
      'https://example.com/a(b)',
      'https://example.com/abc',
      'https://example.com/a?q=1,2',
      'https://example.com/a',
      'https://example.net/b',
    ]);
  });

  test('retains URLs nested in query values instead of splitting targets', () {
    final result = detector.detect(
      'https://example.com/?next=https://example.net/a&value=(b)',
    );
    expect(result.links, hasLength(1));
    expect(
      result.links.single.uri.queryParameters['next'],
      'https://example.net/a',
    );
  });

  test(
    'does not join URLs across source whitespace or repair invalid escapes',
    () {
      final result = detector.detect(
        'https://bbs.\nyamibo.com/thread-1-1-1.html '
        'https://bbs. yamibo.com/thread-1-1-1.html '
        'https://example.com/% https://example.com/%2G',
      );
      expect(result.links, isEmpty);
      expect(result.isLimited, isFalse);
    },
  );

  test('overlong input is limited without parsing a truncated prefix', () {
    final result = detector.detect(
      'https://example.com extra',
      maxInputLength: 20,
    );
    expect(result.isLimited, isTrue);
    expect(result.links, isEmpty);
  });

  test(
    'obvious hard-line continuations do not produce a different prefix URL',
    () {
      final result = detector.detect(
        'https://bbs.yamibo.com/\nthread-123-2-1.html\n'
        'https://bbs.yamibo\n.com/thread-123-2-1.html\n'
        'https://bbs.yamibo.com/thread-123-\r\n2-1.html\n'
        'https://bbs.yamibo.com/\u2028thread-123-2-1.html\n'
        'https://bbs.yamibo.com/\u2029\u3000thread-123-2-1.html\n'
        'https://bbs.yamibo.com\n/forum.php?mod=viewthread&tid=123',
      );
      expect(result.links, isEmpty);
      expect(result.isLimited, isFalse);
      final complete = detector.detect(
        'https://example.com/\nhttps://example.net/a\n文字说明',
      );
      expect(complete.links.map((link) => link.text), [
        'https://example.com/',
        'https://example.net/a',
      ]);
    },
  );

  test('candidate limits count repeated occurrences and expose ambiguity', () {
    const url = 'https://example.com';
    final result = detector.detect('$url $url $url', maxCandidates: 2);
    expect(result.isLimited, isTrue);
    expect(result.links, hasLength(2));
    expect(detector.detect('$url $url', maxCandidates: 2).isLimited, isFalse);
  });

  test(
    'overlong URL is skipped whole and does not consume a later good URL',
    () {
      final result = detector.detect(
        'https://example.com/${'a' * 100} https://example.net/b',
        maxUrlLength: 30,
      );
      expect(result.isLimited, isTrue);
      expect(result.links.map((link) => link.text), ['https://example.net/b']);
    },
  );

  test(
    'long adversarial scheme-like text stays bounded and finds a later URL',
    () {
      final result = detector.detect(
        '${'http:/'.padRight(8, 'x') * 7000} https://example.com/a',
      );
      expect(result.isLimited, isFalse);
      expect(result.links.map((link) => link.text), ['https://example.com/a']);
    },
  );

  test('scan result cannot be mutated by its consumers', () {
    final result = detector.detect('https://example.com');
    expect(() => result.links.clear(), throwsUnsupportedError);
  });
}
