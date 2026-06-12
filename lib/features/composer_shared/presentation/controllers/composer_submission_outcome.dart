/// 子类 `performSubmit` 返回的结果。
///
/// 由基类调度后转换为对外 [ComposerSubmitInvocationResult]，
/// 同时基类负责草稿删除/保留与 errorMessage 写入。
class ComposerSubmissionOutcome {
  const ComposerSubmissionOutcome._({
    required this.success,
    required this.successMessage,
    required this.errorMessage,
  });

  /// 提交成功。可选地带回服务端反馈文案（用于 SnackBar）。
  const ComposerSubmissionOutcome.success({String? message})
      : this._(
          success: true,
          successMessage: message,
          errorMessage: null,
        );

  /// 提交失败。`errorMessage` 是已经经过 presenter 翻译的、可直接展示给用户的文案。
  const ComposerSubmissionOutcome.failure({required String errorMessage})
      : this._(
          success: false,
          successMessage: null,
          errorMessage: errorMessage,
        );

  final bool success;
  final String? successMessage;
  final String? errorMessage;
}

/// 控制器对外暴露的 `submit()` 调用结果。
class ComposerSubmitInvocationResult {
  const ComposerSubmitInvocationResult({
    required this.sent,
    required this.message,
  });

  const ComposerSubmitInvocationResult.notSent({String message = ''})
      : this(sent: false, message: message);

  const ComposerSubmitInvocationResult.sent(String message)
      : this(sent: true, message: message);

  final bool sent;
  final String message;
}
