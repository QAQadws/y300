import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
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
    final code = error.code?.trim() ?? '';
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

  ComposerSubmissionFailure classifyCommand(
    DataCommandFailure failure, {
    required ComposerKind kind,
    required bool outcomeUnknown,
  }) {
    if (outcomeUnknown) {
      return ComposerSubmissionFailure(
        code: ComposerSubmissionFailureCode.outcomeUnknown,
        kind: kind,
        detail: failure.code,
      );
    }
    final protocolCode = failure.code?.trim() ?? '';
    return ComposerSubmissionFailure(
      code:
          _classifyCode(protocolCode) ??
          switch (failure.kind) {
            DataCommandFailureKind.unauthenticated =>
              ComposerSubmissionFailureCode.authenticationRequired,
            DataCommandFailureKind.staleFormhash =>
              ComposerSubmissionFailureCode.credentialExpired,
            DataCommandFailureKind.permissionDenied =>
              ComposerSubmissionFailureCode.permissionDenied,
            DataCommandFailureKind.timeout =>
              ComposerSubmissionFailureCode.timeout,
            DataCommandFailureKind.network =>
              ComposerSubmissionFailureCode.network,
            DataCommandFailureKind.server =>
              ComposerSubmissionFailureCode.server,
            _ => ComposerSubmissionFailureCode.unknown,
          },
      kind: kind,
      detail: failure.code,
    );
  }

  ComposerSubmissionFailureCode? _classifyCode(String code) {
    final normalized = _normalizeDiscuzMessageCode(code);
    if (normalized.loginRequired) {
      return ComposerSubmissionFailureCode.authenticationRequired;
    }
    return switch (normalized.base) {
      'post_type_isnull' => ComposerSubmissionFailureCode.typeRequired,
      'postperm_login_nopermission' ||
      'postperm_login_nopermission_mobile' ||
      'replyperm_login_nopermission' =>
        ComposerSubmissionFailureCode.authenticationRequired,
      'postperm_none_nopermission' ||
      'replyperm_none_nopermission' ||
      'post_forum_newthread_nopermission' ||
      'post_forum_newreply_nopermission' ||
      'postperm_qqonly_nopermission' ||
      'trade_newreply_nopermission' ||
      'group_nopermission' => ComposerSubmissionFailureCode.permissionDenied,
      'post_subject_tooshort' => ComposerSubmissionFailureCode.subjectTooShort,
      'post_subject_toolong' => ComposerSubmissionFailureCode.subjectTooLong,
      'post_too_short' ||
      'post_message_tooshort' ||
      'post_sm_isnull' ||
      'emptymessage' => ComposerSubmissionFailureCode.contentTooShort,
      'post_message_toolong' => ComposerSubmissionFailureCode.contentTooLong,
      'thread_nonexistence' ||
      'forum_nonexistence' ||
      'reply_quotepost_error' ||
      'targetpost_donotbelongto_thisthread' =>
        ComposerSubmissionFailureCode.targetUnavailable,
      'post_thread_closed' ||
      'debate_end' => ComposerSubmissionFailureCode.threadClosed,
      'formhash_invalid' => ComposerSubmissionFailureCode.credentialExpired,
      'post_flood_ctrl' ||
      'post_flood_ctrl_posts_per_hour' ||
      'post_newbie_span' => ComposerSubmissionFailureCode.rateLimited,
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

  ({String base, bool loginRequired}) _normalizeDiscuzMessageCode(String code) {
    var normalized = code.trim().toLowerCase();
    final loginSeparator = normalized.indexOf('//');
    final loginRequired =
        loginSeparator >= 0 &&
        normalized.substring(loginSeparator + 2).split('/').contains('1');
    if (loginSeparator >= 0) {
      normalized = normalized.substring(0, loginSeparator);
    }
    if (normalized.startsWith('mobile:')) {
      normalized = normalized.substring('mobile:'.length);
    }
    return (base: normalized, loginRequired: loginRequired);
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
