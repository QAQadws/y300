import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attachment_preview_resolvers.dart';

void main() {
  test('uploaded resolver exposes only successful local uploads', () {
    final resolver = UploadedComposerAttachmentPreviewResolver(
      imageAttachments: [
        _attachment('1'),
        _attachment('2', status: ComposerImageAttachmentStatus.failed),
        _attachment('3', status: ComposerImageAttachmentStatus.expired),
      ],
    );

    expect(resolver.resolve('1').preview, isA<ComposerLocalImagePreview>());
    expect(
      resolver.resolve('2').availability,
      ComposerAttachmentAvailability.missing,
    );
    expect(
      resolver.resolve('3').availability,
      ComposerAttachmentAvailability.expired,
    );
    expect(
      resolver.resolve('999').availability,
      ComposerAttachmentAvailability.missing,
    );
  });

  test('composite resolver prefers local and falls back to remote', () {
    final local = UploadedComposerAttachmentPreviewResolver(
      imageAttachments: [_attachment('1')],
    );
    final remote = MapComposerAttachmentPreviewResolver(
      resolutions: {
        '1': const ComposerAttachmentResolution(
          aid: '1',
          availability: ComposerAttachmentAvailability.available,
          preview: ComposerRemoteImagePreview(
            url: 'https://bbs.yamibo.com/image.jpg',
            referer: 'https://bbs.yamibo.com/forum.php',
          ),
        ),
        '2': const ComposerAttachmentResolution(
          aid: '2',
          availability: ComposerAttachmentAvailability.available,
          preview: ComposerRemoteImagePreview(
            url: 'https://bbs.yamibo.com/image-2.jpg',
            referer: 'https://bbs.yamibo.com/forum.php',
          ),
        ),
      },
    );
    final resolver = CompositeComposerAttachmentPreviewResolver(
      local: local,
      remote: remote,
    );

    expect(resolver.resolve('1').preview, isA<ComposerLocalImagePreview>());
    expect(resolver.resolve('2').preview, isA<ComposerRemoteImagePreview>());
  });
}

ComposerImageAttachment _attachment(
  String aid, {
  ComposerImageAttachmentStatus status = ComposerImageAttachmentStatus.uploaded,
}) {
  return ComposerImageAttachment(
    localId: 'local-$aid',
    localPath: '/gallery/$aid.jpg',
    fileName: '$aid.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: status,
    aid: aid,
    uploadedAt: DateTime.utc(2026, 6, 8),
  );
}
