import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/services/forum_webview_network_policy_resolver.dart';

void main() {
  const resolver = DefaultForumWebViewNetworkPolicyResolver();

  test('default resolver keeps system UA and app locale preference', () {
    final policy = resolver.resolve(
      Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
    );

    expect(policy.customUserAgent, isNull);
    expect(policy.extraHeaders, isEmpty);
    expect(policy.preferAppLocale, isTrue);
  });
}
