import 'package:yamibo_forum_client/yamibo_forum_client.dart';

/// Shared browser User-Agent strings.
///
/// Every outbound request to the forum must look like a real browser, otherwise
/// the site's WAF (Aliyun anti-bot) answers with a JavaScript challenge instead
/// of the expected JSON/HTML. Keeping these strings in one place lets the
/// low-level [YamiboHttpGateway] fallback, the image header builder, and the
/// HTML client all agree on the same identity instead of drifting apart.
abstract final class BrowserUserAgents {
  /// Desktop Chrome on Windows. Used for desktop-layout HTML pages and images.
  static const String desktop = ForumBrowserUserAgents.desktopChromium;

  /// Mobile Chrome on Android. Used for the mobile (`mobile=2`) HTML pages and
  /// the Discuz mobile JSON API, which is what a phone browser would send.
  static const String mobile = ForumBrowserUserAgents.mobileChromium;
}
