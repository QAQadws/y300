/// Discuz 登录态 cookie 的纯识别逻辑。
///
/// Discuz X 的登录 cookie 命名为 `{cookiepre}auth`，其中 `cookiepre` 形如
/// `EeqY_2132_`（前缀随站点盐值变化、`2132` 为 Discuz 版本号）。为避免把站点
/// 前缀硬编码进判定逻辑，这里按 `_auth` 后缀识别，既能兼容前缀调整，也与参考
/// 实现（yamibo-app 通过 auth cookie 是否存在判断登录态）保持一致。
abstract final class YamiboAuthCookie {
  /// 登录 cookie 名的统一后缀。
  static const String authSuffix = '_auth';

  /// WebView 赢得的阿里云 WAF 通行证 cookie 名，需随登录 cookie 一并回灌 dio。
  static const String wafPassName = 'acw_sc__v2';

  /// 判断一批 cookie 是否已包含有效的登录态。
  ///
  /// 有效条件：存在名字以 `_auth` 结尾、值非空且非删除占位符的 cookie。
  static bool isLoggedIn(Map<String, String> cookies) {
    return cookies.entries.any(_isValidAuthEntry);
  }

  static bool _isValidAuthEntry(MapEntry<String, String> entry) {
    if (!entry.key.toLowerCase().endsWith(authSuffix)) {
      return false;
    }
    final value = entry.value.trim().toLowerCase();
    return value.isNotEmpty && value != 'deleted';
  }
}
