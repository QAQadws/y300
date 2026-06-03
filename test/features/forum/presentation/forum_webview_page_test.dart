import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/tags/data/forum_tag_repository.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';

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
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    expect(find.text('百合会论坛'), findsOneWidget);
    expect(find.byKey(const Key('forum-webview-back-button')), findsNothing);
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
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
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
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-search-button')));
    await tester.pumpAndSettle();

    final page = tester.widget<ForumSearchPage>(find.byType(ForumSearchPage));
    expect(page.context.scope, DiscuzSearchScope.forum);
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
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();

    expect(find.text('功能开发中'), findsOneWidget);
  });

  testWidgets('ForumWebViewPage shows forum display app bar and curForum search', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '页面标题';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    driver.canGoBackValue = true;
    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-back-button')), findsOneWidget);
    expect(find.text('综合区'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-webview-search-button')));
    await tester.pumpAndSettle();

    final page = tester.widget<ForumSearchPage>(find.byType(ForumSearchPage));
    expect(page.context.scope, DiscuzSearchScope.curForum);
    expect(page.context.srhfid, '55');
  });

  testWidgets('ForumWebViewPage thread detail falls back to forum search when fid is unknown', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '主题标题';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    driver.canGoBackValue = true;
    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-back-button')), findsOneWidget);
    expect(find.text('主题标题'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-webview-search-button')));
    await tester.pumpAndSettle();

    final page = tester.widget<ForumSearchPage>(find.byType(ForumSearchPage));
    expect(page.context.scope, DiscuzSearchScope.forum);
  });

  testWidgets('ForumWebViewPage thread detail uses curForum search when fid is known', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '主题标题';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    driver.canGoBackValue = true;
    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2',
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-back-button')), findsOneWidget);
    expect(find.text('综合区'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-webview-search-button')));
    await tester.pumpAndSettle();

    final page = tester.widget<ForumSearchPage>(find.byType(ForumSearchPage));
    expect(page.context.scope, DiscuzSearchScope.curForum);
    expect(page.context.srhfid, '55');
  });

  testWidgets('ForumWebViewPage back button uses driver.goBack when history exists', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '页面标题';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    driver.canGoBackValue = true;
    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pump();

    expect(driver.goBackCallCount, 1);
    expect(
      driver.loadedUris.single.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
  });

  testWidgets('ForumWebViewPage back button loads home when history is unavailable', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '页面标题';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumWebViewDriverProvider.overrideWith((ref) => driver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
          forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
        ],
        child: const MaterialApp(home: ForumWebViewPage()),
      ),
    );
    await tester.pump();

    driver.canGoBackValue = false;
    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pump();

    expect(driver.goBackCallCount, 0);
    expect(driver.loadedUris.length, 2);
    expect(
      driver.loadedUris.last.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
  });
}

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  final List<String> events = <String>[];
  final List<Uri> loadedUris = <Uri>[];
  final List<String> scripts = <String>[];
  final List<_SeededCookieRecord> seededCookies = <_SeededCookieRecord>[];
  String? title;
  bool canGoBackValue = false;
  int goBackCallCount = 0;
  ForumWebViewCallbacks? _callbacks;

  @override
  Widget buildWidget({Key? key}) {
    return Container(key: key);
  }

  Future<void> dispatchPageStarted(String url) async {
    final callbacks = _callbacks;
    if (callbacks == null) {
      return;
    }
    callbacks.onPageStarted(url);
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
  Future<String?> getTitle() async {
    return title;
  }

  @override
  Future<bool> canGoBack() async {
    return canGoBackValue;
  }

  @override
  Future<void> goBack() async {
    goBackCallCount += 1;
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

class _FakeForumTagRepository implements ForumTagRepository {
  @override
  Future<ForumTagLookup> loadLookup() async {
    return ForumTagLookup(
      const <ForumBoardTagSet>[
        ForumBoardTagSet(
          fid: '55',
          name: '综合区',
          tags: <ForumTagDefinition>[],
        ),
      ],
    );
  }
}
