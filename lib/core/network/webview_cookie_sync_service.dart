import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:y300/core/network/cookie_store.dart';

/// WebView 平台 cookie jar 抽象。
///
/// 把 `flutter_inappwebview` 的全局 [inapp.CookieManager] 藏在接口后面，
/// 让 [WebViewCookieSyncService] 不直接耦合平台实现，也便于用假实现做单测。
abstract class WebViewCookieJar {
  /// 读取指定 URL 作用域下的全部 cookie（name → value）。
  Future<Map<String, String>> readCookies(Uri uri);

  /// 清空 WebView 平台 cookie jar，用于登出。
  Future<void> clear();
}

/// 基于 `flutter_inappwebview` [inapp.CookieManager] 的默认实现。
class InAppWebViewCookieJar implements WebViewCookieJar {
  InAppWebViewCookieJar({inapp.CookieManager? cookieManager})
    : _cookieManager = cookieManager ?? inapp.CookieManager.instance();

  final inapp.CookieManager _cookieManager;

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
  Future<void> clear() {
    return _cookieManager.deleteAllCookies();
  }
}

/// 把 WebView 赢得的 cookie 同步进 dio 的 [CookieStore]（WebView → dio 方向）。
///
/// 这是原有架构缺失的一环：真实浏览器（WebView）在手机蜂窝网络下解开阿里云
/// WAF 挑战、并完成登录后，相关 cookie（WAF 通行证 `acw_sc__v2` + 登录态
/// `*_auth`）只存在于 WebView 平台 jar 里；原生 dio 请求拿不到它们就会被 WAF
/// 拦截或视为未登录。此 service 在 WebView 页面加载完成后，把这些 cookie 回灌
/// 到 dio 的存储，使收藏、回复、搜索等 API 功能得以正常工作。
class WebViewCookieSyncService {
  WebViewCookieSyncService({
    required WebViewCookieJar cookieJar,
    required CookieStore cookieStore,
  }) : _cookieJar = cookieJar,
       _cookieStore = cookieStore;

  final WebViewCookieJar _cookieJar;
  final CookieStore _cookieStore;

  /// 读取 [uri] 作用域下的 WebView cookie 并合并写入 dio 存储。
  ///
  /// 返回本次读到的 cookie 快照，供调用方（如登录页）判定登录态；即使写入为
  /// 空也返回快照本身。合并语义由 [CookieStore.saveCookies] 保证，不会误删
  /// 该 host 下其它有效 cookie。
  Future<Map<String, String>> syncToStore(Uri uri) async {
    final cookies = await _cookieJar.readCookies(uri);
    if (cookies.isNotEmpty) {
      await _cookieStore.saveCookies(uri, cookies);
    }
    return cookies;
  }

  /// 登出时清空 WebView 平台 cookie jar，与 dio 侧清理配合，保证重新登录干净。
  Future<void> clearWebViewCookies() {
    return _cookieJar.clear();
  }
}
