import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';

/// Classifies Discuz/network failures without producing locale-specific text.
class ComposerSubmissionFailureClassifier {
  const ComposerSubmissionFailureClassifier();

  ComposerSubmissionFailure classify(
    ApiError error, {
    ComposerKind kind = ComposerKind.reply,
  }) {
    final code = error.code?.trim().toLowerCase() ?? '';
    final message = error.message.trim();
    final loweredMessage = message.toLowerCase();
    final byCode = _classifyCode(code);
    if (byCode != null) {
      return ComposerSubmissionFailure(
        code: byCode,
        kind: kind,
        detail: message.isEmpty ? null : message,
      );
    }

    final classified = switch (error.type) {
      ApiErrorType.unauthorized =>
        ComposerSubmissionFailureCode.authenticationRequired,
      ApiErrorType.timeout => ComposerSubmissionFailureCode.timeout,
      ApiErrorType.network => ComposerSubmissionFailureCode.network,
      ApiErrorType.server => ComposerSubmissionFailureCode.server,
      _ => _classifyMessage(loweredMessage),
    };
    return ComposerSubmissionFailure(
      code: classified ?? ComposerSubmissionFailureCode.unknown,
      kind: kind,
      detail: message.isEmpty ? null : message,
    );
  }

  ComposerSubmissionFailureCode? _classifyCode(String code) {
    return switch (code) {
      'post_type_isnull' => ComposerSubmissionFailureCode.typeRequired,
      'postperm_login_nopermission' =>
        ComposerSubmissionFailureCode.authenticationRequired,
      'post_too_short' ||
      'post_sm_isnull' => ComposerSubmissionFailureCode.contentTooShort,
      'emptymessage' => ComposerSubmissionFailureCode.contentTooShort,
      'formhash_invalid' => ComposerSubmissionFailureCode.credentialExpired,
      'post_flood_ctrl' => ComposerSubmissionFailureCode.rateLimited,
      'seccode_invalid' => ComposerSubmissionFailureCode.captchaRequired,
      'post_pollinvalid' ||
      'pollinvalid' => ComposerSubmissionFailureCode.pollInvalid,
      'polloption_count_invalid' || 'post_polloption_invalid' =>
        ComposerSubmissionFailureCode.pollOptionCountInvalid,
      'post_polltype_isnull' => ComposerSubmissionFailureCode.pollFieldsInvalid,
      _ when code.startsWith('seccode_') =>
        ComposerSubmissionFailureCode.captchaRequired,
      _ => null,
    };
  }

  ComposerSubmissionFailureCode? _classifyMessage(String message) {
    if (_containsAny(message, const [
      'login',
      '登录',
      '未登录',
      '请先登录',
      '登入',
      '未登入',
      '請先登入',
    ])) {
      return ComposerSubmissionFailureCode.authenticationRequired;
    }
    if (_containsAny(message, const [
      'formhash',
      'form hash',
      'session',
      '会话',
      '會話',
    ])) {
      return ComposerSubmissionFailureCode.credentialExpired;
    }
    if (_containsAny(message, const [
      '频率',
      '頻率',
      '间隔',
      '間隔',
      '太快',
      'too fast',
      'flood',
    ])) {
      return ComposerSubmissionFailureCode.rateLimited;
    }
    if (_containsAny(message, const [
      '权限',
      '權限',
      '无权',
      '無權',
      'forbidden',
      'permission',
    ])) {
      return ComposerSubmissionFailureCode.permissionDenied;
    }
    return null;
  }

  bool _containsAny(String source, List<String> patterns) {
    return patterns.any((pattern) => source.contains(pattern.toLowerCase()));
  }
}
