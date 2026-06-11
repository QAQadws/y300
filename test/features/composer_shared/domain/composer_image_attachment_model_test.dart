import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

void main() {
  group('ComposerImageAttachment', () {
    test('previewPath prefers cachePath', () {
      const attachment = ComposerImageAttachment(
        localId: 'local-1',
        localPath: '/gallery/original.jpg',
        fileName: 'original.jpg',
        mimeType: 'image/jpeg',
        order: 0,
        status: ComposerImageAttachmentStatus.local,
        cachePath: '/cache/reply_uploads/local-1/original.jpg',
      );

      expect(attachment.previewPath, '/cache/reply_uploads/local-1/original.jpg');
    });

    test('previewPath falls back to localPath', () {
      const attachment = ComposerImageAttachment(
        localId: 'local-1',
        localPath: '/gallery/original.jpg',
        fileName: 'original.jpg',
        mimeType: 'image/jpeg',
        order: 0,
        status: ComposerImageAttachmentStatus.local,
      );

      expect(attachment.previewPath, '/gallery/original.jpg');
    });

    test('can enter submit payload only when uploaded with non-empty aid', () {
      const uploaded = ComposerImageAttachment(
        localId: 'local-1',
        localPath: '/gallery/original.jpg',
        fileName: 'original.jpg',
        mimeType: 'image/jpeg',
        order: 0,
        status: ComposerImageAttachmentStatus.uploaded,
        aid: '123456',
      );
      const missingAid = ComposerImageAttachment(
        localId: 'local-2',
        localPath: '/gallery/second.jpg',
        fileName: 'second.jpg',
        mimeType: 'image/jpeg',
        order: 1,
        status: ComposerImageAttachmentStatus.uploaded,
      );
      const local = ComposerImageAttachment(
        localId: 'local-3',
        localPath: '/gallery/third.jpg',
        fileName: 'third.jpg',
        mimeType: 'image/jpeg',
        order: 2,
        status: ComposerImageAttachmentStatus.local,
        aid: '789',
      );

      expect(uploaded.canEnterSubmitPayload, isTrue);
      expect(missingAid.canEnterSubmitPayload, isFalse);
      expect(local.canEnterSubmitPayload, isFalse);
    });
  });

  group('ComposerAttachRemain', () {
    test('recognizes unlimited zero and positive remain values', () {
      expect(const ComposerAttachRemain(size: -1, count: -1).hasSizeRemain, isTrue);
      expect(const ComposerAttachRemain(size: -1, count: -1).hasCountRemain, isTrue);
      expect(const ComposerAttachRemain(size: 0, count: 0).hasSizeRemain, isFalse);
      expect(const ComposerAttachRemain(size: 0, count: 0).hasCountRemain, isFalse);
      expect(const ComposerAttachRemain(size: 1024, count: 3).hasSizeRemain, isTrue);
      expect(const ComposerAttachRemain(size: 1024, count: 3).hasCountRemain, isTrue);
    });
  });

  group('ComposerImageUploadPermission', () {
    test('canUploadExtension accepts case-insensitive and dotted extensions', () {
      const permission = ComposerImageUploadPermission(
        uid: '597454',
        uploadHash: 'hash',
        allowedExtensions: {'jpg', 'jpeg', 'png', 'gif'},
        attachRemain: ComposerAttachRemain(size: -1, count: -1),
      );

      expect(permission.canUploadExtension('jpg'), isTrue);
      expect(permission.canUploadExtension('.JPG'), isTrue);
      expect(permission.canUploadExtension('png'), isTrue);
      expect(permission.canUploadExtension('mp3'), isFalse);
      expect(permission.canUploadExtension(''), isFalse);
    });
  });
}
