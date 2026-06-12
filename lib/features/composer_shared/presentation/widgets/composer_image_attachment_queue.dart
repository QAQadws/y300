import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

typedef ComposerImageAttachmentTileKeyBuilder = Key Function(
  ComposerImageAttachment attachment,
);

typedef ComposerImageAttachmentStatusLabelBuilder = String Function(
  ComposerImageAttachment attachment,
);

String defaultComposerImageAttachmentStatusLabel(
  ComposerImageAttachment attachment,
) {
  return switch (attachment.status) {
    ComposerImageAttachmentStatus.local => '等待上传',
    ComposerImageAttachmentStatus.uploading => '上传中',
    ComposerImageAttachmentStatus.uploaded => '已上传',
    ComposerImageAttachmentStatus.failed =>
      attachment.errorMessage?.trim().isNotEmpty == true
          ? '上传失败：${attachment.errorMessage}'
          : '上传失败',
    ComposerImageAttachmentStatus.expired => '已过期',
  };
}

/// 图片附件队列展示。
///
/// 包含：上传进度计数 + 进度条（仅在上传中显示）和每个附件的 ListTile。
/// 调用方注入 widget key（队列容器、计数文本、进度条、每个附件 tile），
/// 让 reply / 发帖页保持各自的稳定 key。
class ComposerImageAttachmentQueue extends StatelessWidget {
  const ComposerImageAttachmentQueue({
    super.key,
    required this.attachments,
    required this.isUploadingImages,
    required this.imageUploadCurrent,
    required this.imageUploadTotal,
    this.containerKey,
    this.uploadCountKey,
    this.uploadProgressKey,
    this.tileKeyBuilder,
    this.statusLabelBuilder = defaultComposerImageAttachmentStatusLabel,
  });

  final List<ComposerImageAttachment> attachments;
  final bool isUploadingImages;
  final int imageUploadCurrent;
  final int imageUploadTotal;
  final Key? containerKey;
  final Key? uploadCountKey;
  final Key? uploadProgressKey;
  final ComposerImageAttachmentTileKeyBuilder? tileKeyBuilder;
  final ComposerImageAttachmentStatusLabelBuilder statusLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: containerKey,
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isUploadingImages) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '第 $imageUploadCurrent/$imageUploadTotal 张',
                key: uploadCountKey,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: LinearProgressIndicator(
                key: uploadProgressKey,
                value: imageUploadTotal > 0
                    ? imageUploadCurrent / imageUploadTotal
                    : null,
              ),
            ),
          ],
          for (final attachment in attachments)
            ListTile(
              key: tileKeyBuilder?.call(attachment),
              leading: const Icon(Icons.image_outlined),
              title: Text(attachment.fileName),
              subtitle: Text(
                '${attachment.mimeType} · ${statusLabelBuilder(attachment)}',
              ),
              dense: true,
            ),
        ],
      ),
    );
  }
}
