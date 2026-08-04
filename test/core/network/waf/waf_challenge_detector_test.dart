import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/waf/waf_challenge_detector.dart';

void main() {
  group('WafChallengeDetector', () {
    test('detects the captured acw_sc__v2 script shape', () {
      const body =
          "<html><script>var arg1='96ABD6F4FB95815FA0387BF0988673420';"
          "document.cookie='acw_sc__v2=pass;path=/';"
          'document.location.reload();</script></html>';

      expect(WafChallengeDetector.isChallengeBody(body), isTrue);
      expect(
        WafChallengeDetector.detect(body: body, statusCode: 200, method: 'GET'),
        WafChallengeEvidence.scriptBody,
      );
    });

    test('detects an explicit challenge in a bytes response', () {
      const body = "<html><script>var arg1='ABC';</script></html>";
      expect(WafChallengeDetector.isChallengeBody(body.codeUnits), isTrue);
    });

    test(
      'does not mistake normal HTML mentioning acw_sc__v2 for a challenge',
      () {
        const body = '<html><body>Cookie name: acw_sc__v2</body></html>';
        expect(WafChallengeDetector.isChallengeBody(body), isFalse);
      },
    );

    test('classifies a bare GET 405 as weak challenge evidence', () {
      expect(
        WafChallengeDetector.detect(
          body: 'Method Not Allowed',
          statusCode: 405,
          method: 'GET',
        ),
        WafChallengeEvidence.httpMethodNotAllowed,
      );
    });

    test('does not classify a bare POST 405 as recoverable', () {
      expect(
        WafChallengeDetector.detect(
          body: 'Method Not Allowed',
          statusCode: 405,
          method: 'POST',
        ),
        isNull,
      );
    });

    test('keeps ordinary JSON and HTML negative', () {
      expect(
        WafChallengeDetector.isChallengeBody('{"Variables":{"formhash":"fh"}}'),
        isFalse,
      );
      expect(
        WafChallengeDetector.isChallengeBody(
          '<html><head><title>Forum</title></head><body>ok</body></html>',
        ),
        isFalse,
      );
    });
  });
}
