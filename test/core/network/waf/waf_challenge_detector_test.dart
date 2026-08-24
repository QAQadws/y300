import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/waf/waf_challenge_detector.dart';

void main() {
  group('WafChallengeDetector', () {
    test('classifies HTTP 405 as the only challenge evidence', () {
      expect(
        WafChallengeDetector.detect(statusCode: 405),
        WafChallengeEvidence.httpStatus405,
      );
    });

    test('keeps every non-405 status negative', () {
      for (final status in <int?>[null, 200, 302, 400, 403, 404, 500, 503]) {
        expect(WafChallengeDetector.detect(statusCode: status), isNull);
      }
    });
  });
}
