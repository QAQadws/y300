import 'dart:async';

import 'package:y300/core/network/waf/waf_challenge_passer.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';

/// 阿里云 WAF 通行证的响应式恢复协调器。
///
/// 单例、进程内共享；把三个动作粘合起来：
///
/// 1. 在 [WafChallengePasser] 里跑真实浏览器，让挑战脚本自然写入
///    `acw_sc__v2`（与登录态 cookie 同源同域）。
/// 2. 调用 [WebViewCookieSyncService.syncToStore] 把 WebView cookie jar
///    回灌 dio 的 [CookieStore]，让原生请求带上通行证。
/// 3. 用 [passWindow] 兜住"刚刚通过挑战又立刻被 WAF 拦"的异常场景——
///    默认 30 分钟，与阿里云 WAF 的默认放行窗口一致。窗口内避免死循环
///    重复刷新（真正的原因往往不是 cookie 过期而是 IP 指纹或速率限制，
///    再刷新一次只会浪费一个 WebView）。
///
/// 并发处理：同一时刻只允许一次刷新在飞（[Future] 去重），所有并发触发
/// 者共享同一份结果。
class WafChallengeResolver {
  WafChallengeResolver({
    required WafChallengePasser challengePasser,
    required WebViewCookieSyncService cookieSyncService,
    required Uri siteUri,
    Duration passWindow = const Duration(minutes: 30),
    DateTime Function() clock = _systemClock,
  })  : _passer = challengePasser,
        _syncService = cookieSyncService,
        _siteUri = siteUri,
        _passWindow = passWindow,
        _clock = clock;

  final WafChallengePasser _passer;
  final WebViewCookieSyncService _syncService;
  final Uri _siteUri;
  final Duration _passWindow;
  final DateTime Function() _clock;

  DateTime? _lastSuccessAt;
  Future<bool>? _inFlight;

  /// 触发一次刷新：加载 [triggeringUri] 让 WAF 挑战跑完，再同步 cookie。
  ///
  /// 返回 `true` 代表这一次调用（或它去重合并到的那次调用）真正完成了一次
  /// 刷新且成功；返回 `false` 代表：
  /// - 距离上次成功刷新还在 [passWindow] 之内——跳过，避免循环刷新
  /// - passer 抛异常或同步失败
  ///
  /// 调用方拿到 `false` 时应放弃自动重试、把错误如实抛给用户，否则会陷入
  /// "无限刷新 + 无限失败"的坏循环。
  Future<bool> ensureFreshPass({required Uri triggeringUri}) {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final lastSuccess = _lastSuccessAt;
    if (lastSuccess != null &&
        _clock().difference(lastSuccess) < _passWindow) {
      return Future.value(false);
    }

    final future = _runRefresh(triggeringUri);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  Future<bool> _runRefresh(Uri triggeringUri) async {
    try {
      await _passer.pass(triggeringUri);
      await _syncService.syncToStore(_siteUri);
      _lastSuccessAt = _clock();
      return true;
    } catch (_) {
      // 保守失败：不更新 _lastSuccessAt，让下一次挑战仍能触发刷新。
      return false;
    }
  }

  /// 只做测试可见：重置内部状态，便于隔离测试用例之间的状态泄漏。
  /// 生产代码不应依赖该方法。
  void debugReset() {
    _lastSuccessAt = null;
    _inFlight = null;
  }

  static DateTime _systemClock() => DateTime.now();
}
