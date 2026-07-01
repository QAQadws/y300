import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/waf/waf_challenge_detector.dart';

void main() {
  group('WafChallengeDetector.isChallenge', () {
    test('detects Aliyun WAF challenge with var arg1 marker', () {
      const body =
          "<html><script>var arg1='CF759CB6E008C1573E1DBFB5D16448BB12A51EDO';"
          '(function(a, c){var G=aOj, d=a();while(![])})();'
          '</script></html>';
      expect(WafChallengeDetector.isChallenge(body), isTrue);
    });

    test('detects challenge with acw_sc__v2 marker even without arg1', () {
      const body = '<html><script>document.cookie="acw_sc__v2=abcdef; path=/";'
          'location.href=location.pathname;</script></html>';
      expect(WafChallengeDetector.isChallenge(body), isTrue);
    });

    test('detects challenge served with DOCTYPE prelude', () {
      const body = "<!DOCTYPE html><html><script>var arg1='X';</script></html>";
      expect(WafChallengeDetector.isChallenge(body), isTrue);
    });

    test('detects bare <script> shell without <html> wrapper', () {
      const body = "<script>var arg1='ABCDEF';</script>";
      expect(WafChallengeDetector.isChallenge(body), isTrue);
    });

    test('detects challenge in bytes payload (image request masquerade)', () {
      const text =
          "<html><script>var arg1='DEADBEEF';</script></html>";
      final bytes = text.codeUnits;
      expect(WafChallengeDetector.isChallenge(bytes), isTrue);
    });

    test('does not misfire on normal Discuz JSON response', () {
      const body = '{"Version":"4","Charset":"utf-8","Variables":{"formhash":"fh"}}';
      expect(WafChallengeDetector.isChallenge(body), isFalse);
    });

    test('does not misfire on normal mobile HTML page', () {
      const body = '<html><head><title>论坛首页</title></head>'
          '<body><ul class="list"><li>hello</li></ul></body></html>';
      expect(WafChallengeDetector.isChallenge(body), isFalse);
    });

    test('does not misfire on HTML that merely contains an "arg1" word', () {
      // Prose containing "arg1" but without an inline <script arg1=> pattern.
      const body = '<html><body>Discuss the "arg1" parameter here.</body></html>';
      expect(WafChallengeDetector.isChallenge(body), isFalse);
    });

    test('returns false for empty body', () {
      expect(WafChallengeDetector.isChallenge(''), isFalse);
      expect(WafChallengeDetector.isChallenge(const <int>[]), isFalse);
      expect(WafChallengeDetector.isChallenge(null), isFalse);
    });

    test('returns false for non-string non-bytes payloads', () {
      expect(WafChallengeDetector.isChallenge(const <String, int>{'a': 1}), isFalse);
      expect(WafChallengeDetector.isChallenge(42), isFalse);
    });

    test('detects challenge even if body has trailing garbage past 4 KiB head', () {
      final buffer = StringBuffer()
        ..write("<html><script>var arg1='XY';</script>");
      for (var i = 0; i < 10000; i++) {
        buffer.write('padding-');
      }
      expect(WafChallengeDetector.isChallenge(buffer.toString()), isTrue);
    });
  });
}
