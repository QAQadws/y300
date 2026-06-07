import 'package:y300/core/network/api_result.dart';

class ReplySubmissionErrorPresenter {
  const ReplySubmissionErrorPresenter();

  String present(ApiError error) {
    final message = error.message.trim();
    final lowered = message.toLowerCase();

    if (error.type == ApiErrorType.unauthorized ||
        _containsAny(lowered, const ['login', '登录', '未登录', '请先登录'])) {
      return '登录状态已失效，请重新登录后再试';
    }
    if (_containsAny(lowered, const ['formhash', 'form hash', 'session', '会话'])) {
      return '回复凭证已失效，请刷新登录态后重试';
    }
    if (_containsAny(lowered, const ['频率', '间隔', '太快', 'too fast', 'flood'])) {
      return '回复太频繁了，请稍后再试';
    }
    if (_containsAny(lowered, const ['权限', '无权', 'forbidden', 'permission'])) {
      return '当前账号权限不足，无法发送回复';
    }
    if (error.type == ApiErrorType.timeout) {
      return '网络超时，请稍后重试';
    }
    if (error.type == ApiErrorType.network || error.type == ApiErrorType.server) {
      return '网络异常，请稍后重试';
    }
    if (message.isNotEmpty) {
      return message;
    }
    return '发送回复失败，请稍后重试';
  }

  bool _containsAny(String source, List<String> patterns) {
    for (final pattern in patterns) {
      if (source.contains(pattern.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}
