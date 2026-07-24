import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_transient_feedback.dart';

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

  test('reports successful and failed status transitions once', () {
    final tracker = ComposerUploadFeedbackTracker();

    expect(
      tracker.update(_state(status: ComposerImageAttachmentStatus.local)),
      isEmpty,
    );
    expect(
      tracker.update(_state(status: ComposerImageAttachmentStatus.uploaded)),
      ['image.jpg 已上传'],
    );
    expect(
      tracker.update(_state(status: ComposerImageAttachmentStatus.uploaded)),
      isEmpty,
    );
    expect(
      tracker.update(
        _state(
          status: ComposerImageAttachmentStatus.failed,
          errorMessage: '服务器拒绝',
        ),
      ),
      ['image.jpg 上传失败：服务器拒绝'],
    );
    expect(
      tracker.update(
        _state(
          status: ComposerImageAttachmentStatus.failed,
          errorMessage: '服务器拒绝',
        ),
      ),
      isEmpty,
    );
  });

  test('normalizes unknown network errors to stable user feedback', () {
    final tracker = ComposerUploadFeedbackTracker();

    expect(tracker.update(_state()), isEmpty);
    expect(tracker.update(_state(imageUploadError: '网络异常: unknown')), [
      '图片上传失败，请重试',
    ]);
    expect(tracker.update(_state(imageUploadError: '网络异常: unknown')), isEmpty);
  });

  test('normalizes empty and generic attachment errors', () {
    final tracker = ComposerUploadFeedbackTracker();

    expect(
      tracker.update(_state(status: ComposerImageAttachmentStatus.local)),
      isEmpty,
    );
    expect(
      tracker.update(
        _state(status: ComposerImageAttachmentStatus.failed, errorMessage: ''),
      ),
      ['image.jpg 上传失败，请重试'],
    );
    expect(
      tracker.update(
        _state(
          status: ComposerImageAttachmentStatus.failed,
          errorMessage: '网络异常，图片上传失败',
        ),
      ),
      isEmpty,
    );
  });

  test('preserves explicit server rejection details', () {
    expect(normalizeComposerUploadError('服务器拒绝：文件过大'), '服务器拒绝：文件过大');
    expect(
      normalizeComposerUploadError('SocketException: connection reset'),
      ComposerUploadFeedbackTracker.genericUploadFailure,
    );
  });
}

_TestComposerState _state({
  ComposerImageAttachmentStatus? status,
  String? errorMessage,
  String? imageUploadError,
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
              errorMessage: errorMessage,
            ),
          ],
    isUploadingImages: false,
    imageUploadCurrent: 0,
    imageUploadTotal: 0,
    imageUploadError: imageUploadError,
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
    super.imageUploadError,
  });
}
