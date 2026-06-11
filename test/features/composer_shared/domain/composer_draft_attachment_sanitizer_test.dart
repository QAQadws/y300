import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_sanitizer.dart';

void main() {
  group('ComposerDraftAttachmentSanitizer', () {
    const sanitizer = ComposerDraftAttachmentSanitizer();
    final now = DateTime.utc(2026, 6, 8, 12);

    ComposerImageAttachment attachment({
      required String localId,
      required int order,
      required DateTime? uploadedAt,
      String? aid,
      ComposerImageAttachmentStatus status =
          ComposerImageAttachmentStatus.uploaded,
    }) {
      return ComposerImageAttachment(
        localId: localId,
        localPath: '/gallery/$localId.jpg',
        fileName: '$localId.jpg',
        mimeType: 'image/jpeg',
        order: order,
        status: status,
        aid: aid,
        uploadedAt: uploadedAt,
      );
    }

    test('removes expired attachment metadata and matching attach code', () {
      final expired = attachment(
        localId: 'expired',
        order: 0,
        aid: '123',
        uploadedAt: now.subtract(const Duration(hours: 24)),
      );
      final fresh = attachment(
        localId: 'fresh',
        order: 1,
        aid: '456',
        uploadedAt: now.subtract(const Duration(hours: 23)),
      );

      final result = sanitizer.sanitize(
        message: '正文\n[attach]123[/attach]\n[attach]456[/attach]',
        imageAttachments: [expired, fresh],
        now: now,
      );

      expect(result.changed, isTrue);
      expect(result.imageAttachments, [fresh]);
      expect(result.removedAttachments, [expired]);
      expect(result.message, '正文\n[attach]456[/attach]');
    });

    test('keeps fresh attachment and matching attach code', () {
      final fresh = attachment(
        localId: 'fresh',
        order: 0,
        aid: '456',
        uploadedAt: now.subtract(const Duration(hours: 1)),
      );

      final result = sanitizer.sanitize(
        message: '正文\n[attach]456[/attach]',
        imageAttachments: [fresh],
        now: now,
      );

      expect(result.changed, isFalse);
      expect(result.imageAttachments, [fresh]);
      expect(result.message, '正文\n[attach]456[/attach]');
    });

    test('expired attachment without aid does not alter message', () {
      final expiredWithoutAid = attachment(
        localId: 'expired',
        order: 0,
        uploadedAt: now.subtract(const Duration(hours: 24)),
      );

      final result = sanitizer.sanitize(
        message: '正文\n[attach]123[/attach]',
        imageAttachments: [expiredWithoutAid],
        now: now,
      );

      expect(result.imageAttachments, isEmpty);
      expect(result.removedAttachments, [expiredWithoutAid]);
      expect(result.message, '正文\n[attach]123[/attach]');
    });

    test('expired status is removed even without uploadedAt', () {
      final expired = attachment(
        localId: 'expired',
        order: 0,
        aid: '123',
        uploadedAt: null,
        status: ComposerImageAttachmentStatus.expired,
      );

      final result = sanitizer.sanitize(
        message: '正文\n[attach]123[/attach]',
        imageAttachments: [expired],
        now: now,
      );

      expect(result.imageAttachments, isEmpty);
      expect(result.message, '正文');
    });

    test('sanitization is idempotent', () {
      final expired = attachment(
        localId: 'expired',
        order: 0,
        aid: '123',
        uploadedAt: now.subtract(const Duration(hours: 24)),
      );

      final first = sanitizer.sanitize(
        message: '正文\n[attach]123[/attach]',
        imageAttachments: [expired],
        now: now,
      );
      final second = sanitizer.sanitize(
        message: first.message,
        imageAttachments: first.imageAttachments,
        now: now,
      );

      expect(first.message, '正文');
      expect(second.message, '正文');
      expect(second.imageAttachments, isEmpty);
      expect(second.changed, isFalse);
    });
  });
}
