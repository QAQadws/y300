import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('closing login during bootstrap cannot seed stale credentials', (
    tester,
  ) async {
    final cookieStore = _DelayedReadCookieStore();
    final cookieJar = _RecordingWebViewCookieJar();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webViewCookieSyncServiceProvider.overrideWithValue(
            WebViewCookieSyncService(
              cookieJar: cookieJar,
              cookieStore: cookieStore,
            ),
          ),
        ],
        child: const LocalizedTestApp(home: LoginWebViewPage()),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    cookieStore.pendingRead.complete({'auth': 'expired-account'});
    await tester.pump();

    expect(cookieJar.writeCount, 0);
    expect(tester.takeException(), isNull);
  });
}

final class _DelayedReadCookieStore extends CookieStore {
  final Completer<Map<String, String>> pendingRead =
      Completer<Map<String, String>>();

  @override
  Future<Map<String, String>> readCookieMap(Uri uri) => pendingRead.future;
}

final class _RecordingWebViewCookieJar implements WebViewCookieJar {
  int writeCount = 0;

  @override
  Future<Map<String, String>> readCookies(Uri uri) async => {};

  @override
  Future<void> writeCookies(Uri uri, Map<String, String> cookies) async {
    writeCount++;
  }

  @override
  Future<void> clear() async {}
}
