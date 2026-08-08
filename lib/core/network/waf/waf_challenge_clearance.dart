/// Result of a native request made after WebView cookies have been synced.
///
/// The WebView document is deliberately not used as proof of clearance: a
/// WAF can return a non-empty error document and still reject the native
/// client. Only [cleared] is sufficient to finish background recovery.
enum WafChallengeClearance { cleared, challenged, inconclusive }

typedef WafChallengeClearanceProbe =
    Future<WafChallengeClearance> Function({
      required Uri uri,
      required String userAgent,
    });

typedef WafChallengeCookieSync = Future<void> Function(Uri uri);

/// Orders the two halves of verification: WebView cookies must reach the
/// shared native store before the probe is allowed to make its decision.
final class WafChallengeVerificationService {
  const WafChallengeVerificationService({
    required WafChallengeCookieSync syncCookies,
    required WafChallengeClearanceProbe probe,
  }) : _syncCookies = syncCookies,
       _probe = probe;

  final WafChallengeCookieSync _syncCookies;
  final WafChallengeClearanceProbe _probe;

  Future<WafChallengeClearance> verify({
    required Uri uri,
    required String userAgent,
  }) async {
    await _syncCookies(uri);
    return _probe(uri: uri, userAgent: userAgent);
  }
}
