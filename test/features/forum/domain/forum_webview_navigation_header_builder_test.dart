import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_network_policy_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigation_header_builder.dart';

void main() {
  test('builder uses same-host referrer and strips cookie style headers', () {
    final builder = DefaultForumWebViewNavigationHeaderBuilder(
      localeReader: () => const Locale('zh', 'CN'),
    );
    final headers = builder.build(
      targetUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      ),
      referrerUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      ),
      policy: const ForumWebViewNetworkPolicy(
        extraHeaders: <String, String>{
          'Cookie': 'a=b',
          'User-Agent': 'custom',
          'X-Test': '1',
        },
      ),
    );

    final headerKeys = headers.keys.map((key) => key.toLowerCase()).toSet();
    expect(
      headers['Referer'],
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    expect(headers['Accept-Language'], 'zh-CN,zh;q=0.9,en;q=0.8');
    expect(headers['X-Test'], '1');
    expect(headerKeys, isNot(contains('cookie')));
    expect(headerKeys, isNot(contains('user-agent')));
  });

  test('builder falls back to site root and fallback locale header', () {
    final builder = DefaultForumWebViewNavigationHeaderBuilder(
      localeReader: () => null,
    );
    final headers = builder.build(
      targetUri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
      referrerUri: Uri.parse('https://example.com/thread/123'),
      policy: const ForumWebViewNetworkPolicy(),
    );

    expect(headers['Referer'], 'https://bbs.yamibo.com/');
    expect(headers['Accept-Language'], 'zh-CN,zh;q=0.9,en;q=0.8');
  });

  test(
    'builder honors explicit accept-language when app locale preference is disabled',
    () {
      final builder = DefaultForumWebViewNavigationHeaderBuilder(
        localeReader: () => const Locale('ja', 'JP'),
      );
      final headers = builder.build(
        targetUri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
        policy: const ForumWebViewNetworkPolicy(
          preferAppLocale: false,
          extraHeaders: <String, String>{'accept-language': 'en-US,en;q=0.8'},
        ),
      );

      expect(headers['Accept-Language'], 'en-US,en;q=0.8');
    },
  );
}
