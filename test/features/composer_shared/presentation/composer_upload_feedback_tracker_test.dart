import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_text_resolver.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_transient_feedback.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  test('does not notify for restored uploaded attachments', () {
    final tracker = ComposerUploadFeedbackTracker();

    expect(
      tracker.update(_state(status: ComposerImageAttachmentStatus.uploaded)),
      isEmpty,
    );
    expect(
      tracker.update(_state(status: ComposerImageAttachmentStatus.uploaded)),
      isEmpty,
    );
  });

  test('reports successful and failed transitions as structured data once', () {
    final tracker = ComposerUploadFeedbackTracker();

    expect(
      tracker.update(_state(status: ComposerImageAttachmentStatus.local)),
      isEmpty,
    );
    final uploaded = tracker.update(
      _state(status: ComposerImageAttachmentStatus.uploaded),
    );
    expect(uploaded.single.type, ComposerUploadFeedbackType.uploaded);
    expect(uploaded.single.fileName, 'image.jpg');
    expect(
      ComposerTextResolver.uploadFeedback(
        AppLocalizationsZhTw(),
        uploaded.single,
      ),
      contains('image.jpg'),
    );
    expect(
      tracker.update(_state(status: ComposerImageAttachmentStatus.uploaded)),
      isEmpty,
    );

    final failed = tracker.update(
      _state(
        status: ComposerImageAttachmentStatus.failed,
        attachmentFailureCode: ComposerImageUploadFailureCode.server,
      ),
    );
    expect(failed.single.type, ComposerUploadFeedbackType.failed);
    expect(failed.single.failure?.code, ComposerImageUploadFailureCode.server);
    expect(
      tracker.update(
        _state(
          status: ComposerImageAttachmentStatus.failed,
          attachmentFailureCode: ComposerImageUploadFailureCode.server,
        ),
      ),
      isEmpty,
    );
  });

  test('reports a changed batch failure once', () {
    final tracker = ComposerUploadFeedbackTracker();

    expect(tracker.update(_state()), isEmpty);
    final feedback = tracker.update(
      _state(
        imageUploadFailure: const ComposerImageUploadFailure(
          code: ComposerImageUploadFailureCode.network,
        ),
      ),
    );
    expect(feedback.single.type, ComposerUploadFeedbackType.batchFailure);
    expect(
      feedback.single.failure?.code,
      ComposerImageUploadFailureCode.network,
    );
    expect(
      ComposerTextResolver.uploadFeedback(
        AppLocalizationsZh(),
        feedback.single,
      ),
      contains('网络'),
    );
    expect(
      tracker.update(
        _state(
          imageUploadFailure: const ComposerImageUploadFailure(
            code: ComposerImageUploadFailureCode.network,
          ),
        ),
      ),
      isEmpty,
    );
  });
}

_TestComposerState _state({
  ComposerImageAttachmentStatus? status,
  ComposerImageUploadFailureCode? attachmentFailureCode,
  ComposerImageUploadFailure? imageUploadFailure,
}) {
  return _TestComposerState(
    message: '',
    useSignature: true,
    isSubmitting: false,
    restoredDraft: false,
    imageAttachments: status == null
        ? const <ComposerImageAttachment>[]
        : [
            ComposerImageAttachment(
              localId: 'image-1',
              localPath: '/tmp/image.jpg',
              fileName: 'image.jpg',
              mimeType: 'image/jpeg',
              order: 0,
              status: status,
              failureCode: attachmentFailureCode,
            ),
          ],
    isUploadingImages: false,
    imageUploadCurrent: 0,
    imageUploadTotal: 0,
    imageUploadFailure: imageUploadFailure,
  );
}

class _TestComposerState extends ComposerStateBase {
  const _TestComposerState({
    required super.message,
    required super.useSignature,
    required super.isSubmitting,
    required super.restoredDraft,
    required super.imageAttachments,
    required super.isUploadingImages,
    required super.imageUploadCurrent,
    required super.imageUploadTotal,
    super.imageUploadFailure,
  });
}
