import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_attachment_verification_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_draft_attachment_preview_resolver.dart';

void main() {
  test('hides unverified local previews after a failed catalog request', () {
    final resolver = ComposerDraftAttachmentPreviewResolver(
      imageAttachments: [_attachment(cachePath: '/cache/12.jpg')],
      verification: ComposerDraftAttachmentVerification.failed(
        unverifiedAids: const <String>{'12'},
      ),
      fileExists: (_) => true,
    );

    expect(
      resolver.resolve('12').availability,
      ComposerAttachmentAvailability.missing,
    );
  });

  test('prefers a verified managed copy over the remote thumbnail', () {
    final resolver = ComposerDraftAttachmentPreviewResolver(
      imageAttachments: [_attachment(cachePath: '/cache/12.jpg')],
      verification: ComposerDraftAttachmentVerification.verified(
        imagesByAid: <String, ComposerUnusedImage>{'12': _remote()},
        invalidAidCount: 0,
      ),
      fileExists: (path) => path == '/cache/12.jpg',
    );

    expect(resolver.resolve('12').preview, isA<ComposerLocalImagePreview>());
  });

  test('falls back to remote for valid aid with no local managed copy', () {
    final resolver = ComposerDraftAttachmentPreviewResolver(
      imageAttachments: [_attachment()],
      verification: ComposerDraftAttachmentVerification.verified(
        imagesByAid: <String, ComposerUnusedImage>{'12': _remote()},
        invalidAidCount: 0,
      ),
      fileExists: (_) => false,
    );

    final preview = resolver.resolve('12').preview;
    expect(preview, isA<ComposerRemoteImagePreview>());
    expect((preview! as ComposerRemoteImagePreview).url, contains('aid=12'));
  });

  test(
    'keeps a current-session upload visible before verification is needed',
    () {
      final resolver = ComposerDraftAttachmentPreviewResolver(
        imageAttachments: [_attachment()],
        verification: const ComposerDraftAttachmentVerification.notRequired(),
        fileExists: (_) => true,
      );

      expect(resolver.resolve('12').preview, isA<ComposerLocalImagePreview>());
    },
  );

  test('keeps a new local upload after older draft aids were checked', () {
    final resolver = ComposerDraftAttachmentPreviewResolver(
      imageAttachments: [_attachment()],
      verification: ComposerDraftAttachmentVerification.verified(
        imagesByAid: <String, ComposerUnusedImage>{'99': _remote(aid: '99')},
        checkedAids: const <String>{'99'},
        invalidAidCount: 0,
      ),
      fileExists: (_) => true,
    );

    expect(resolver.resolve('12').preview, isA<ComposerLocalImagePreview>());
  });
}

ComposerImageAttachment _attachment({String? cachePath}) {
  return ComposerImageAttachment(
    localId: 'local-12',
    localPath: '/gallery/12.jpg',
    fileName: '12.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: ComposerImageAttachmentStatus.uploaded,
    aid: '12',
    uploadedAt: DateTime.utc(2026, 8, 3),
    cachePath: cachePath,
  );
}

ComposerUnusedImage _remote({String aid = '12'}) {
  return ComposerUnusedImage(
    aid: aid,
    thumbnailUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=image&aid=$aid&size=300x300',
    ),
  );
}
