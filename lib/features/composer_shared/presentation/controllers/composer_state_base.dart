import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 编辑器通用状态字段。
///
/// reply 与 posting 各自的 state 类继承本基类，再补充自己的业务字段
/// （如 reply 的 `target` / `preparation`、posting 的 `subject` / `metadata`）。
/// 基类只持有"哪一类业务都需要的字段"，避免 reply 反向依赖 posting 的字段。
abstract class ComposerStateBase {
  const ComposerStateBase({
    required this.message,
    required this.useSignature,
    required this.isSubmitting,
    required this.restoredDraft,
    required this.imageAttachments,
    required this.isUploadingImages,
    required this.imageUploadCurrent,
    required this.imageUploadTotal,
    this.errorMessage,
    this.imageUploadError,
  });

  final String message;
  final bool useSignature;
  final bool isSubmitting;
  final bool restoredDraft;
  final List<ComposerImageAttachment> imageAttachments;
  final bool isUploadingImages;
  final int imageUploadCurrent;
  final int imageUploadTotal;
  final String? errorMessage;
  final String? imageUploadError;
}
