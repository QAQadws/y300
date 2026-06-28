import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 附件相关的业务能力封装。同时服务于回复（reply）与发帖（newthread）两类场景：
/// 上层通过 [prepareUpload] 拉取一次 `module=checkpost` 的权限快照，
/// 然后串行调用 [uploadImage] 上传具体图片。
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
