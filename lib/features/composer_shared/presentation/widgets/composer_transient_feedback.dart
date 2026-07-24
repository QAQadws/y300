import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

void showComposerSnackBar(BuildContext context, String message) {
  showTransientSnackBar(context, message);
}

class ComposerUploadFeedbackTracker {
  static const genericUploadFailure = '图片上传失败，请重试';

  bool _initialized = false;
  Set<String> _uploadedIds = const <String>{};
  Set<String> _failedIds = const <String>{};
  String? _lastError;

  List<String> update(ComposerStateBase state) {
    final uploadedIds = {
      for (final attachment in state.imageAttachments)
        if (attachment.isUploaded) attachment.localId,
    };
    final failedIds = {
      for (final attachment in state.imageAttachments)
        if (attachment.status == ComposerImageAttachmentStatus.failed)
          attachment.localId,
    };
    final normalizedError = normalizeComposerUploadError(
      state.imageUploadError,
    );

    if (!_initialized) {
      _initialized = true;
      _uploadedIds = uploadedIds;
      _failedIds = failedIds;
      _lastError = normalizedError;
      return const <String>[];
    }

    final messages = <String>[];
    for (final attachment in state.imageAttachments) {
      if (attachment.isUploaded && !_uploadedIds.contains(attachment.localId)) {
        messages.add('${attachment.fileName} 已上传');
      }
      if (attachment.status == ComposerImageAttachmentStatus.failed &&
          !_failedIds.contains(attachment.localId)) {
        final reason = normalizeComposerUploadError(attachment.errorMessage);
        if (reason == null || reason == genericUploadFailure) {
          messages.add('${attachment.fileName} 上传失败，请重试');
        } else {
          messages.add('${attachment.fileName} 上传失败：$reason');
        }
      }
    }

    if (messages.isEmpty &&
        normalizedError != null &&
        normalizedError != _lastError) {
      messages.add(normalizedError);
    }

    _uploadedIds = uploadedIds;
    _failedIds = failedIds;
    _lastError = normalizedError;
    return messages;
  }
}

String? normalizeComposerUploadError(String? raw) {
  if (raw == null) {
    return null;
  }
  final message = raw.trim();
  if (message.isEmpty) {
    return ComposerUploadFeedbackTracker.genericUploadFailure;
  }
  final lower = message.toLowerCase();
  if (lower == 'unknown' ||
      lower.contains('network error: unknown') ||
      lower.contains('网络异常: unknown') ||
      lower.contains('网络异常') ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('clientexception') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower == '图片上传失败') {
    return ComposerUploadFeedbackTracker.genericUploadFailure;
  }
  return message;
}
