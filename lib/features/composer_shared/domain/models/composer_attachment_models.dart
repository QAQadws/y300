/// 附件相关领域模型，在自制回复页与（后续）发帖页之间共享。
///
/// Phase 1 仅做迁移：把原 `ReplyImageAttachment` 等类型从 reply 模块抽到 composer_shared。
/// 字段含义保持不变，由对应的旧 `Reply*` 名称通过 typedef 别名继续暴露给现有调用方，
/// 避免一次性改动所有引用点。后续阶段再做"二次提纯"。
enum ComposerImageAttachmentStatus {
  local,
  uploading,
  uploaded,
  failed,
  expired,
}

class ComposerImageAttachment {
  const ComposerImageAttachment({
    required this.localId,
    required this.localPath,
    required this.fileName,
    required this.mimeType,
    required this.order,
    required this.status,
    this.aid,
    this.uploadedAt,
    this.errorMessage,
    this.cachePath,
  });

  final String localId;
  final String localPath;
  final String fileName;
  final String mimeType;
  final int order;
  final ComposerImageAttachmentStatus status;
  final String? aid;
  final DateTime? uploadedAt;
  final String? errorMessage;
  final String? cachePath;

  bool get isUploaded => status == ComposerImageAttachmentStatus.uploaded;

  bool get hasAid => aid != null && aid!.trim().isNotEmpty;

  bool get canEnterSubmitPayload => isUploaded && hasAid;

  String get previewPath {
    final cached = cachePath;
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }
    return localPath;
  }
}

class ComposerAttachRemain {
  const ComposerAttachRemain({
    required this.size,
    required this.count,
  });

  final int size;
  final int count;

  bool get hasSizeRemain => size < 0 || size > 0;

  bool get hasCountRemain => count < 0 || count > 0;
}

class ComposerImageUploadPermission {
  const ComposerImageUploadPermission({
    required this.uid,
    required this.uploadHash,
    required this.allowedExtensions,
    required this.attachRemain,
    this.username,
    this.formHash,
  });

  final String uid;
  final String uploadHash;
  final Set<String> allowedExtensions;
  final ComposerAttachRemain attachRemain;
  final String? username;
  final String? formHash;

  bool canUploadExtension(String extension) {
    final normalized = extension.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.startsWith('.')) {
      return allowedExtensions.contains(normalized.substring(1));
    }
    return allowedExtensions.contains(normalized);
  }
}

class ComposerPickedImage {
  const ComposerPickedImage({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.originalIndex,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int originalIndex;
}

class ComposerLocalImageFile {
  const ComposerLocalImageFile({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final String mimeType;
}

class ComposerImageUploadResponse {
  const ComposerImageUploadResponse({
    required this.aid,
    required this.rawBody,
    required this.statusCode,
  });

  final String aid;
  final Object? rawBody;
  final int? statusCode;
}

class ComposerUploadedImage {
  const ComposerUploadedImage({
    required this.localId,
    required this.aid,
    required this.uploadedAt,
  });

  final String localId;
  final String aid;
  final DateTime uploadedAt;
}
