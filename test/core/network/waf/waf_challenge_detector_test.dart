import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/waf/waf_challenge_detector.dart';

void main() {
  group('WafChallengeDetector', () {
    test('forwards normalized header evidence from the shared policy', () {
      expect(
        WafChallengeDetector.detect(
          statusCode: 200,
          headers: const {
            'X-Tengine-Error': [' DENIED BY HTTP_AUTO_RATELIMIT '],
          },
        ),
        WafChallengeEvidence.httpAutoRatelimit,
      );
      expect(
        WafChallengeDetector.detect(
          statusCode: 200,
          headers: const {
            'x-tengine-error': ['denied by Referer ACL'],
          },
        ),
        isNull,
      );
    });

    test('retains HTTP 405 challenge evidence', () {
      expect(
        WafChallengeDetector.detect(statusCode: 405),
        WafChallengeEvidence.httpStatus405,
      );
    });

    test('keeps non-405 statuses without header evidence negative', () {
      for (final status in <int?>[null, 200, 302, 400, 403, 404, 500, 503]) {
        expect(WafChallengeDetector.detect(statusCode: status), isNull);
      }
    });
  });
}
