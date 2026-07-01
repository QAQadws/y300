import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:y300/core/network/browser_user_agents.dart';

/// 在真实浏览器环境中打开 [uri] 让阿里云 WAF 的 JS 挑战脚本执行完毕，从而把
/// `acw_sc__v2` 通行证 cookie 落到平台 cookie jar 里。
///
/// 抽成接口的原因：
/// 1. dio 单元测试不会带 flutter_inappwebview 平台通道，直接依赖 headless
///    WebView 会让测试全部无法初始化——注入假实现即可绕开。
/// 2. 若将来切换到其它 WebView 实现（webview_flutter / 系统 Chrome Tabs），
///    只要提供新的实现类即可。
abstract class WafChallengePasser {
  /// 加载 [uri] 直到页面稳定或超时，让 WAF 挑战脚本自然写入 cookie。
  ///
  /// 成功语义仅代表"WebView 完成加载"，不代表挑战一定被通过——通过与否由
  /// 后续 cookie 同步 + 重发请求的实际结果决定。
  Future<void> pass(Uri uri);
}

/// 基于 [inapp.HeadlessInAppWebView] 的默认实现。
///
/// 关键行为：
/// - 用移动端浏览器 UA 与 [BrowserUserAgents.mobile] 保持一致，避免因 UA
///   差异触发额外的 WAF 指纹分歧。
/// - 用"加载完成后再静置 [_settleDelay]"来吸收挑战脚本触发的自动跳转：
///   典型挑战流是"挑战页 onLoadStop → JS 写 cookie → 跳到真实页 → 再一次
///   onLoadStop"，只在最后一次静置期结束后才结算，避免过早拿到未完成的
///   cookie 快照。
/// - 硬性 [timeout] 兜底，无论如何都会释放资源，避免 WebView 泄漏。
class HeadlessInAppWebViewChallengePasser implements WafChallengePasser {
  HeadlessInAppWebViewChallengePasser({
    Duration timeout = const Duration(seconds: 15),
    Duration settleDelay = const Duration(milliseconds: 600),
    String userAgent = BrowserUserAgents.mobile,
  })  : _timeout = timeout,
        _settleDelay = settleDelay,
        _userAgent = userAgent;

  final Duration _timeout;
  final Duration _settleDelay;
  final String _userAgent;

  @override
  Future<void> pass(Uri uri) async {
    final completer = Completer<void>();
    Timer? settleTimer;
    Timer? hardTimeoutTimer;
    late inapp.HeadlessInAppWebView headless;

    void completeOnce() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    void scheduleSettle() {
      settleTimer?.cancel();
      settleTimer = Timer(_settleDelay, completeOnce);
    }

    headless = inapp.HeadlessInAppWebView(
      initialUrlRequest: inapp.URLRequest(url: inapp.WebUri(uri.toString())),
      initialSettings: inapp.InAppWebViewSettings(
        userAgent: _userAgent,
        javaScriptEnabled: true,
        // 挑战脚本会 document.cookie 写入 acw_sc__v2；确保 WebView 允许
        // 该 cookie 在 headless 模式下也持久化到平台 jar。
        thirdPartyCookiesEnabled: true,
        clearCache: false,
      ),
      onLoadStart: (controller, url) {
        // 新的一次加载开始，取消上一次静置计时——等新页面稳定后再结算。
        settleTimer?.cancel();
      },
      onLoadStop: (controller, url) => scheduleSettle(),
      onReceivedError: (controller, request, error) {
        // 加载失败也算流程终结，让上层根据 cookie 现状决定是否已通过。
        scheduleSettle();
      },
    );

    hardTimeoutTimer = Timer(_timeout, completeOnce);

    try {
      await headless.run();
      await completer.future;
    } finally {
      settleTimer?.cancel();
      hardTimeoutTimer.cancel();
      // dispose 是幂等的；即使 run 抛错也要清掉平台侧 WebView，避免泄漏。
      try {
        await headless.dispose();
      } catch (_) {
        // best-effort：dispose 抛错不影响调用方。
      }
    }
  }
}
