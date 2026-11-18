import 'package:yamibo_forum_client/yamibo_forum_client.dart';

typedef WafChallengeEvidence = ForumWafEvidence;

/// Host compatibility adapter for the shared header-only WAF policy.
///
/// Response bodies are intentionally never inspected. This keeps challenge
/// detection deterministic and avoids buffering or parsing arbitrary payloads.
abstract final class WafChallengeDetector {
  static ForumWafResponseDecision classify({
    required int? statusCode,
    Map<String, List<String>> headers = const {},
  }) =>
      ForumWafResponsePolicy.classify(statusCode: statusCode, headers: headers);

  static WafChallengeEvidence? detect({
    required int? statusCode,
    Map<String, List<String>> headers = const {},
  }) => classify(statusCode: statusCode, headers: headers).evidence;
}
