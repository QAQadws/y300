import 'package:y300/features/auth/data/models/auth_session_models.dart';

/// WebView 登录流程在单次页面加载后的判定结果。
///
/// 用密封类而非可空 [SessionInfo] 表达三种语义清晰的状态，避免用 null 混淆
/// “还没登录”与“登录了但校验失败”。
sealed class WebViewLoginProgress {
  const WebViewLoginProgress();
}

/// 尚未检测到登录态（用户还没提交，或 auth cookie 未出现）。
class WebViewLoginPending extends WebViewLoginProgress {
  const WebViewLoginPending();
}

/// 已登录且会话校验通过，携带用于填充全局会话的 [SessionInfo]。
class WebViewLoginSucceeded extends WebViewLoginProgress {
  const WebViewLoginSucceeded(this.session);

  final SessionInfo session;
}

/// 检测到 auth cookie，但随后的 API 会话校验失败（如网络异常）。
class WebViewLoginFailed extends WebViewLoginProgress {
  const WebViewLoginFailed(this.message);

  final String message;
}
