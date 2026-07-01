/// Shared browser User-Agent strings.
///
/// Every outbound request to the forum must look like a real browser, otherwise
/// the site's WAF (Aliyun anti-bot) answers with a JavaScript challenge instead
/// of the expected JSON/HTML. Keeping these strings in one place lets the
/// low-level [YamiboHttpGateway] fallback, the image header builder, and the
/// HTML client all agree on the same identity instead of drifting apart.
abstract final class BrowserUserAgents {
  /// Desktop Chrome on Windows. Used for desktop-layout HTML pages and images.
  static const String desktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// Mobile Chrome on Android. Used for the mobile (`mobile=2`) HTML pages and
  /// the Discuz mobile JSON API, which is what a phone browser would send.
  static const String mobile =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';
}
