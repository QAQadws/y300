import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:y300/core/network/cookie_store.dart';

/// WebView 平台 cookie jar 抽象。
///
/// 把 `flutter_inappwebview` 的全局 [inapp.CookieManager] 藏在接口后面，
/// 让 [WebViewCookieSyncService] 不直接耦合平台实现，也便于用假实现做单测。
abstract class WebViewCookieJar {
  /// 读取指定 URL 作用域下的全部 cookie（name → value）。
  Future<Map<String, String>> readCookies(Uri uri);

  /// Merge cookies into the WebView jar without clearing unrelated entries.
  Future<void> writeCookies(Uri uri, Map<String, String> cookies);

  /// 清空 WebView 平台 cookie jar，用于登出。
  Future<void> clear();
}

/// 基于 `flutter_inappwebview` [inapp.CookieManager] 的默认实现。
///
/// 平台通道懒加载：`CookieManager.instance()` 会立刻 touch flutter_inappwebview
/// 平台通道，在单元测试环境（无平台绑定）里会抛 assertion。为了让上层 provider
/// 图能在纯 dart 测试里正常展开——只有真正调用 [readCookies] / [clear] 时才
/// 会向平台通道要 manager——把实例化推迟到首次使用。
class InAppWebViewCookieJar implements WebViewCookieJar {
  InAppWebViewCookieJar({inapp.CookieManager? cookieManager})
    : _explicitCookieManager = cookieManager;

  final inapp.CookieManager? _explicitCookieManager;
  inapp.CookieManager? _cachedCookieManager;

  inapp.CookieManager get _cookieManager {
    return _explicitCookieManager ??
        (_cachedCookieManager ??= inapp.CookieManager.instance());
  }

  @override
  Future<Map<String, String>> readCookies(Uri uri) async {
    final cookies = await _cookieManager.getCookies(
      url: inapp.WebUri(uri.toString()),
    );
    final result = <String, String>{};
    for (final cookie in cookies) {
      final name = cookie.name.trim();
      final value = cookie.value?.toString().trim() ?? '';
      if (name.isEmpty) {
        continue;
      }
      result[name] = value;
    }
    return result;
  }

  @override
  Future<void> writeCookies(Uri uri, Map<String, String> cookies) async {
    final webUri = inapp.WebUri(uri.toString());
    for (final entry in cookies.entries) {
      final name = entry.key.trim();
      final value = entry.value.trim();
      if (name.isEmpty || value.isEmpty || value.toLowerCase() == 'deleted') {
        continue;
      }
      await _cookieManager.setCookie(
        url: webUri,
        name: name,
        value: value,
        path: '/',
      );
    }
  }

  @override
  Future<void> clear() {
    return _cookieManager.deleteAllCookies();
  }
}

/// 在共享原生 [CookieStore] 与平台 WebView jar 之间合并当前 Cookie。
///
/// 局部网页、登录与 WAF 共用平台存储；初始化只合并凭据，安全登出才清空。
/// 页面和账号守卫限制异步回灌，避免迟到的浏览器快照覆盖新会话。
class WebViewCookieSyncService {
  WebViewCookieSyncService({
    required WebViewCookieJar cookieJar,
    required CookieStore cookieStore,
  }) : _cookieJar = cookieJar,
       _cookieStore = cookieStore;

  final WebViewCookieJar _cookieJar;
  final CookieStore _cookieStore;
  Future<void> _browserMutationTail = Future<void>.value();
  int _browserMutationGeneration = 0;
  int _pendingBrowserMutations = 0;
  int _clearGeneration = 0;
  int _pendingClears = 0;

  /// 读取 [uri] 作用域下的 WebView cookie 并合并写入 dio 存储。
  ///
  /// Returns only a committed snapshot. Page/account expiry, concurrent native
  /// cookie mutations, browser seeds and clears invalidate an in-flight read.
  Future<Map<String, String>> syncToStore(
    Uri uri, {
    bool Function()? isCurrent,
  }) async {
    final generation = _browserMutationGeneration;
    final revision = _cookieStore.revision;
    bool canCommit() =>
        _pendingBrowserMutations == 0 &&
        generation == _browserMutationGeneration &&
        isCurrent?.call() != false;
    if (!canCommit()) return const {};
    final cookies = await _cookieJar.readCookies(uri);
    if (cookies.isEmpty || !canCommit()) return const {};
    final committed = await _cookieStore.saveCookiesIfCurrent(
      uri,
      cookies,
      expectedRevision: revision,
      isCurrent: canCommit,
    );
    return committed && canCommit() ? cookies : const {};
  }

  /// Seeds the browser with the native cookie snapshot before navigation.
  ///
  /// This is merge-only in both directions: security verification must never
  /// clear an auth cookie, formhash-related cookie, or unrelated WebView state.
  Future<Map<String, String>> seedFromStore(
    Uri uri, {
    bool Function()? isCurrent,
  }) {
    final generation = _clearGeneration;
    bool canSeed() =>
        _pendingClears == 0 &&
        generation == _clearGeneration &&
        isCurrent?.call() != false;
    if (!canSeed()) return Future.value(const {});
    return _enqueueBrowserMutation(() async {
      if (!canSeed()) return const <String, String>{};
      // A queued page has not read a snapshot yet, so use the latest native
      // revision when its turn starts rather than expiring it while it waits.
      final revision = _cookieStore.revision;
      bool snapshotIsCurrent() =>
          canSeed() && revision == _cookieStore.revision;
      final rawCookies = await _cookieStore.readCookieMap(uri);
      if (!snapshotIsCurrent()) return const <String, String>{};
      final cookies = <String, String>{};
      for (final entry in rawCookies.entries) {
        final name = entry.key.trim();
        final value = entry.value.trim();
        if (name.isEmpty || value.isEmpty || value.toLowerCase() == 'deleted') {
          continue;
        }
        cookies[name] = value;
      }
      if (cookies.isEmpty) return const <String, String>{};

      _browserMutationGeneration++;
      _pendingBrowserMutations++;
      try {
        for (final entry in cookies.entries) {
          if (!snapshotIsCurrent()) return const <String, String>{};
          // Platform writes cannot be cancelled. Check between cookies and
          // serialize logout's clear after any write that has already started.
          await _cookieJar.writeCookies(uri, {entry.key: entry.value});
        }
        return snapshotIsCurrent() ? cookies : const <String, String>{};
      } finally {
        _pendingBrowserMutations--;
        _browserMutationGeneration++;
      }
    });
  }

  /// 登出时清空 WebView 平台 cookie jar，与 dio 侧清理配合，保证重新登录干净。
  Future<void> clearWebViewCookies() async {
    _clearGeneration++;
    _browserMutationGeneration++;
    _pendingClears++;
    _pendingBrowserMutations++;
    try {
      await _enqueueBrowserMutation(_cookieJar.clear);
    } finally {
      _pendingClears--;
      _pendingBrowserMutations--;
      _clearGeneration++;
      _browserMutationGeneration++;
    }
  }

  Future<T> _enqueueBrowserMutation<T>(Future<T> Function() mutation) {
    final result = _browserMutationTail.then((_) => mutation());
    _browserMutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
