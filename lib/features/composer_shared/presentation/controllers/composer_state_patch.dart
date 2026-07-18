import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 基类向子类下发"状态增量"的值对象。
///
/// 基类不知道子类 state 的具体形状（reply 有 `target`/`preparation`，
/// posting 有 `subject`/`metadata`），所以把通用字段以 patch 形式表达，
/// 由子类的 `applyPatch` 负责 merge 进自己的 `copyWith`。
///
/// 命名约定：
/// - `null` 字段表示"不修改"。
/// - `clearXxx == true` 表示"显式清空"，优先级高于具体值。
class ComposerStatePatch {
  const ComposerStatePatch({
    this.message,
    this.useSignature,
    this.isSubmitting,
    this.restoredDraft,
    this.imageAttachments,
    this.isUploadingImages,
    this.imageUploadCurrent,
    this.imageUploadTotal,
    this.errorMessage,
    this.imageUploadError,
    this.clearErrorMessage = false,
    this.clearImageUploadError = false,
  });

  final String? message;
  final bool? useSignature;
  final bool? isSubmitting;
  final bool? restoredDraft;
  final List<ComposerImageAttachment>? imageAttachments;
  final bool? isUploadingImages;
  final int? imageUploadCurrent;
  final int? imageUploadTotal;
  final String? errorMessage;
  final String? imageUploadError;
  final bool clearErrorMessage;
  final bool clearImageUploadError;
}
