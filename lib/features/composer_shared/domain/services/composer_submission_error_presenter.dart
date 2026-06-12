import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';

/// 把后端 / 网络层的错误翻译成对终端用户友好的中文提示。
///
/// Phase 3 起 [present] 接受 `ComposerKind`（默认仍是 reply，调用方不需要立刻
/// 改签名）。reply / newthread 分别有自己的文案表，命中表里键值时按 kind 给
/// 不同提示；未命中时统一走"网络/超时/未登录"等基础分支，最后兜底为接口原文。
class ComposerSubmissionErrorPresenter {
  const ComposerSubmissionErrorPresenter();

  String present(
    ApiError error, {
    ComposerKind kind = ComposerKind.reply,
  }) {
    final code = error.code?.trim().toLowerCase() ?? '';
    final message = error.message.trim();
    final loweredMessage = message.toLowerCase();

    // 1. 优先按 messageval（接口码）分发，命中即返回业务化文案。
    final byCode = _presentByCode(code: code, kind: kind);
    if (byCode != null) {
      return byCode;
    }

    // 2. 通用文本/类型分支：未登录 / 凭证 / 超时 / 网络 / 权限。
    if (error.type == ApiErrorType.unauthorized ||
        _containsAny(loweredMessage, const ['login', '登录', '未登录', '请先登录'])) {
      return '登录状态已失效，请重新登录后再试';
    }
    if (_containsAny(
      loweredMessage,
      const ['formhash', 'form hash', 'session', '会话'],
    )) {
      return _credentialMessage(kind);
    }
    if (_containsAny(
      loweredMessage,
      const ['频率', '间隔', '太快', 'too fast', 'flood'],
    )) {
      return _floodMessage(kind);
    }
    if (_containsAny(
      loweredMessage,
      const ['权限', '无权', 'forbidden', 'permission'],
    )) {
      return _permissionMessage(kind);
    }
    if (error.type == ApiErrorType.timeout) {
      return '网络超时，请稍后重试';
    }
    if (error.type == ApiErrorType.network ||
        error.type == ApiErrorType.server) {
      return '网络异常，请稍后重试';
    }

    // 3. 兜底：接口原文，再没有就给通用失败文案。
    if (message.isNotEmpty) {
      return message;
    }
    return _genericFailureMessage(kind);
  }

  String? _presentByCode({required String code, required ComposerKind kind}) {
    if (code.isEmpty) {
      return null;
    }
    switch (code) {
      case 'post_type_isnull':
        return kind == ComposerKind.newThread
            ? '该版块要求选择主题分类，请先选择'
            : null;
      case 'postperm_login_nopermission':
        return '请先登录或检查发帖权限';
      case 'post_too_short':
      case 'post_sm_isnull':
        return kind == ComposerKind.newThread ? '标题或内容过短' : '回复内容过短';
      case 'post_flood_ctrl':
        return _floodMessage(kind);
      case 'seccode_invalid':
        return '需要验证码，请暂时改用网页发布';
    }
    if (code.startsWith('seccode_')) {
      return '需要验证码，请暂时改用网页发布';
    }
    return null;
  }

  String _credentialMessage(ComposerKind kind) {
    return kind == ComposerKind.newThread
        ? '发帖凭证已失效，请刷新登录态后重试'
        : '回复凭证已失效，请刷新登录态后重试';
  }

  String _floodMessage(ComposerKind kind) {
    return kind == ComposerKind.newThread
        ? '发帖过于频繁，请稍后再试'
        : '回复太频繁了，请稍后再试';
  }

  String _permissionMessage(ComposerKind kind) {
    return kind == ComposerKind.newThread
        ? '当前账号权限不足，无法发帖'
        : '当前账号权限不足，无法发送回复';
  }

  String _genericFailureMessage(ComposerKind kind) {
    return kind == ComposerKind.newThread ? '发帖失败，请稍后重试' : '发送回复失败，请稍后重试';
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
