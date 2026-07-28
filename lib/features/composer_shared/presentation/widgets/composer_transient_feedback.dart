import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

void showComposerSnackBar(BuildContext context, String message) {
  showTransientSnackBar(context, message);
}

class ComposerUploadFeedbackTracker {
  bool _initialized = false;
  Set<String> _uploadedIds = const <String>{};
  Set<String> _failedIds = const <String>{};
  String? _lastFailureSignature;

  List<ComposerUploadFeedback> update(ComposerStateBase state) {
    final uploadedIds = {
      for (final attachment in state.imageAttachments)
        if (attachment.isUploaded) attachment.localId,
    };
    final failedIds = {
      for (final attachment in state.imageAttachments)
        if (attachment.status == ComposerImageAttachmentStatus.failed)
          attachment.localId,
    };
    final batchFailure = state.imageUploadFailure;
    final failureSignature = batchFailure == null
        ? null
        : '${batchFailure.code.name}:${batchFailure.detail ?? ''}';

    if (!_initialized) {
      _initialized = true;
      _uploadedIds = uploadedIds;
      _failedIds = failedIds;
      _lastFailureSignature = failureSignature;
      return const <ComposerUploadFeedback>[];
    }

    final feedback = <ComposerUploadFeedback>[];
    for (final attachment in state.imageAttachments) {
      if (attachment.isUploaded && !_uploadedIds.contains(attachment.localId)) {
        feedback.add(ComposerUploadFeedback.uploaded(attachment.fileName));
      }
      if (attachment.status == ComposerImageAttachmentStatus.failed &&
          !_failedIds.contains(attachment.localId)) {
        feedback.add(
          ComposerUploadFeedback.failed(
            fileName: attachment.fileName,
            failure: ComposerImageUploadFailure(
              code:
                  attachment.failureCode ??
                  ComposerImageUploadFailureCode.unknown,
            ),
          ),
        );
      }
    }

    if (feedback.isEmpty &&
        batchFailure != null &&
        failureSignature != _lastFailureSignature) {
      feedback.add(ComposerUploadFeedback.batchFailure(batchFailure));
    }

    _uploadedIds = uploadedIds;
    _failedIds = failedIds;
    _lastFailureSignature = failureSignature;
    return feedback;
  }
}

enum ComposerUploadFeedbackType { uploaded, failed, batchFailure }

class ComposerUploadFeedback {
  const ComposerUploadFeedback._({
    required this.type,
    this.fileName,
    this.failure,
  });

  const ComposerUploadFeedback.uploaded(String fileName)
    : this._(type: ComposerUploadFeedbackType.uploaded, fileName: fileName);

  const ComposerUploadFeedback.failed({
    required String fileName,
    required ComposerImageUploadFailure failure,
  }) : this._(
         type: ComposerUploadFeedbackType.failed,
         fileName: fileName,
         failure: failure,
       );

  const ComposerUploadFeedback.batchFailure(ComposerImageUploadFailure failure)
    : this._(type: ComposerUploadFeedbackType.batchFailure, failure: failure);

  final ComposerUploadFeedbackType type;
  final String? fileName;
  final ComposerImageUploadFailure? failure;
}
