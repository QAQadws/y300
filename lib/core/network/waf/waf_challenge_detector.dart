enum WafChallengeEvidence { httpStatus405 }

/// Classifies the forum's WAF challenge solely from its HTTP status.
///
/// Response bodies are intentionally never inspected. This keeps challenge
/// detection deterministic and avoids buffering or parsing arbitrary payloads.
abstract final class WafChallengeDetector {
  static WafChallengeEvidence? detect({required int? statusCode}) {
    return statusCode == 405 ? WafChallengeEvidence.httpStatus405 : null;
  }
}
