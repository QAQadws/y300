import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';

void main() {
  testWidgets('ForumWebViewPage shows home app bar and seeds cookies before load', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final cookieStore = _FakeCookieStore(
      header: 'auth=token123; saltkey=abc',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(cookieStore),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    expect(find.text('百合会论坛'), findsOneWidget);
    expect(find.byKey(const Key('forum-webview-search-button')), findsOneWidget);
    expect(find.byKey(const Key('forum-webview-more-button')), findsOneWidget);
    expect(driver.events, <String>['initialize', 'seedCookies', 'load']);
    expect(driver.seededCookies.single.domain, 'bbs.yamibo.com');
    expect(
      driver.seededCookies.single.cookies,
      <String, String>{'auth': 'token123', 'saltkey': 'abc'},
    );
    expect(
      driver.loadedUris.single.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
  });

  testWidgets('ForumWebViewPage cleans chrome when page finishes loading', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    await tester.pump();

    expect(driver.scripts.length, 1);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(driver.scripts.length, 2);
  });

  testWidgets('ForumWebViewPage search button opens ForumSearchPage', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-search-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ForumSearchPage), findsOneWidget);
  });

  testWidgets('ForumWebViewPage more menu shows disabled placeholder item', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();

    expect(find.text('功能开发中'), findsOneWidget);
  });
}

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  final List<String> events = <String>[];
  final List<Uri> loadedUris = <Uri>[];
  final List<String> scripts = <String>[];
  final List<_SeededCookieRecord> seededCookies = <_SeededCookieRecord>[];
  ForumWebViewCallbacks? _callbacks;

  @override
  Widget buildWidget({Key? key}) {
    return Container(key: key);
  }

  Future<void> dispatchPageFinished(String url) async {
    final callbacks = _callbacks;
    if (callbacks == null) {
      return;
    }
    await callbacks.onPageFinished(url);
  }

  @override
  Future<void> initialize({required ForumWebViewCallbacks callbacks}) async {
    events.add('initialize');
    _callbacks = callbacks;
  }

  @override
  Future<void> load(Uri uri) async {
    events.add('load');
    loadedUris.add(uri);
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }

  @override
  Future<void> seedCookies({
    required String domain,
    required Map<String, String> cookies,
    String path = '/',
  }) async {
    events.add('seedCookies');
    seededCookies.add(
      _SeededCookieRecord(
        domain: domain,
        cookies: Map<String, String>.from(cookies),
        path: path,
      ),
    );
  }
}

class _SeededCookieRecord {
  const _SeededCookieRecord({
    required this.domain,
    required this.cookies,
    required this.path,
  });

  final String domain;
  final Map<String, String> cookies;
  final String path;
}

class _FakeCookieStore extends CookieStore {
  _FakeCookieStore({this.header});

  final String? header;

  @override
  Future<String?> readCookieHeader(Uri uri) async {
    return header;
  }
}
