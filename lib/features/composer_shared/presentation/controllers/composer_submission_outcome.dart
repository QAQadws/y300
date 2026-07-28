import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';

/// 子类 `performSubmit` 返回的结果。
///
/// 由基类调度后转换为对外 [ComposerSubmitInvocationResult]，
/// 同时基类负责草稿删除/保留与结构化 failure 写入。
class ComposerSubmissionOutcome {
  const ComposerSubmissionOutcome._({
    required this.success,
    required this.rawSuccessDetail,
    required this.failure,
  });

  const ComposerSubmissionOutcome.success({String? rawDetail})
    : this._(success: true, rawSuccessDetail: rawDetail, failure: null);

  const ComposerSubmissionOutcome.failure({
    required ComposerSubmissionFailure failure,
  }) : this._(success: false, rawSuccessDetail: null, failure: failure);

  final bool success;
  final String? rawSuccessDetail;
  final ComposerSubmissionFailure? failure;
}

/// 控制器对外暴露的 `submit()` 调用结果。
class ComposerSubmitInvocationResult {
  const ComposerSubmitInvocationResult({
    required this.sent,
    this.rawSuccessDetail,
    this.failure,
  });

  const ComposerSubmitInvocationResult.notSent({ComposerFailure? failure})
    : this(sent: false, failure: failure);

  const ComposerSubmitInvocationResult.sent({String? rawDetail})
    : this(sent: true, rawSuccessDetail: rawDetail);

  final bool sent;
  final String? rawSuccessDetail;
  final ComposerFailure? failure;
}
