import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 附件相关的 App 侧业务能力封装，同时服务于回复与发帖编辑器。
///
/// 来源协议由 package contract 承接；上层先通过 [prepareUpload] 获取不透明
/// 权限快照，再串行调用 [uploadImage]，不接触 uid 或 upload hash。
abstract class ComposerAttachmentRepository {
  Future<ApiResult<ComposerImageUploadPermission>> prepareUpload({
    required String fid,
  });

  Future<ApiResult<ComposerUploadedImage>> uploadImage({
    required String fid,
    required ComposerImageUploadPermission permission,
    required ComposerImageAttachment attachment,
    void Function(double progress)? onProgress,
  });
}

/// Optional capability for cancelling an active package-backed upload call.
abstract interface class ComposerAttachmentUploadCancellation {
  void cancelActiveUpload();
}
