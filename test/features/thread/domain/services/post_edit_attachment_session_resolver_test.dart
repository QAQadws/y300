import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_attachment_session_resolver.dart';

void main() {
  final remote = PostEditExistingImage(
    aid: '1',
    imageUri: Uri.parse('https://bbs.yamibo.com/image.jpg'),
    isAssociated: true,
    fileName: 'remote.jpg',
  );
  final local = ComposerImageAttachment(
    localId: 'local-1',
    localPath: '/tmp/local.jpg',
    fileName: 'local.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: ComposerImageAttachmentStatus.uploaded,
    aid: '2',
  );

  test('uses the session precedence and keeps remote images remote', () {
    final resolver = PostEditAttachmentSessionResolver(
      session: PostEditAttachmentSession.fromImages(
        [remote],
        deletingAids: const {'3'},
        deletedAidTombstones: const {'4'},
      ),
      localAttachments: [local],
      referer: 'https://bbs.yamibo.com/forum.php?mod=post',
    );

    expect(resolver.resolve('1').preview, isA<ComposerRemoteImagePreview>());
    expect(resolver.resolve('2').preview, isA<ComposerLocalImagePreview>());
    expect(
      resolver.resolve('3').availability,
      ComposerAttachmentAvailability.deleting,
    );
    expect(
      resolver.resolve('4').availability,
      ComposerAttachmentAvailability.deleted,
    );
    expect(
      resolver.resolve('unknown').availability,
      ComposerAttachmentAvailability.missing,
    );
  });

  test('tombstone wins over a local upload with the same aid', () {
    final resolver = PostEditAttachmentSessionResolver(
      session: PostEditAttachmentSession.fromImages(
        const <PostEditExistingImage>[],
        deletedAidTombstones: const {'2'},
      ),
      localAttachments: [local],
      referer: 'https://bbs.yamibo.com/forum.php',
    );

    expect(
      resolver.resolve('2').availability,
      ComposerAttachmentAvailability.deleted,
    );
    expect(resolver.resolve('2').preview, isNull);
  });
}
