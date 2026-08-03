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
      String? cachePath,
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
        cachePath: cachePath,
      );
    }

    test('14-day expiry clears only the managed local copy', () {
      final expired = attachment(
        localId: 'expired',
        order: 0,
        aid: '123',
        uploadedAt: now.subtract(const Duration(days: 14)),
        cachePath: '/cache/expired.jpg',
      );
      final fresh = attachment(
        localId: 'fresh',
        order: 1,
        aid: '456',
        uploadedAt: now.subtract(const Duration(days: 13)),
        cachePath: '/cache/fresh.jpg',
      );

      final result = sanitizer.sanitize(
        message: '正文\n[attach]123[/attach]\n[attach]456[/attach]',
        imageAttachments: [expired, fresh],
        now: now,
      );

      expect(result.changed, isTrue);
      expect(result.imageAttachments, hasLength(2));
      expect(result.imageAttachments.first.aid, '123');
      expect(result.imageAttachments.first.cachePath, isNull);
      expect(result.imageAttachments.last.cachePath, '/cache/fresh.jpg');
      expect(result.removedAttachments, isEmpty);
      expect(result.expiredCacheAttachments, [expired]);
      expect(result.message, '正文\n[attach]123[/attach]\n[attach]456[/attach]');
    });

    test('keeps fresh attachment and matching attach code', () {
      final fresh = attachment(
        localId: 'fresh',
        order: 0,
        aid: '456',
        uploadedAt: now.subtract(const Duration(hours: 1)),
        cachePath: '/cache/fresh.jpg',
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

    test('old attachment without a managed copy remains unchanged', () {
      final oldWithoutCache = attachment(
        localId: 'old',
        order: 0,
        uploadedAt: now.subtract(const Duration(days: 30)),
      );

      final result = sanitizer.sanitize(
        message: '正文\n[attach]123[/attach]',
        imageAttachments: [oldWithoutCache],
        now: now,
      );

      expect(result.changed, isFalse);
      expect(result.imageAttachments, [oldWithoutCache]);
      expect(result.removedAttachments, isEmpty);
      expect(result.message, '正文\n[attach]123[/attach]');
    });

    test('legacy expired status preserves aid metadata and BBCode', () {
      final expired = attachment(
        localId: 'expired',
        order: 0,
        aid: '123',
        uploadedAt: null,
        cachePath: '/cache/legacy.jpg',
        status: ComposerImageAttachmentStatus.expired,
      );

      final result = sanitizer.sanitize(
        message: '正文\n[attach]123[/attach]',
        imageAttachments: [expired],
        now: now,
      );

      expect(result.imageAttachments, hasLength(1));
      expect(
        result.imageAttachments.single.status,
        ComposerImageAttachmentStatus.uploaded,
      );
      expect(result.imageAttachments.single.aid, '123');
      expect(result.imageAttachments.single.cachePath, isNull);
      expect(result.removedAttachments, isEmpty);
      expect(result.expiredCacheAttachments, [expired]);
      expect(result.message, '正文\n[attach]123[/attach]');
    });

    test('legacy expired record without aid is removed', () {
      final expired = attachment(
        localId: 'expired',
        order: 0,
        uploadedAt: null,
        status: ComposerImageAttachmentStatus.expired,
      );

      final result = sanitizer.sanitize(
        message: '正文',
        imageAttachments: [expired],
        now: now,
      );

      expect(result.imageAttachments, isEmpty);
      expect(result.removedAttachments, [expired]);
      expect(result.message, '正文');
    });

    test('sanitization is idempotent', () {
      final expired = attachment(
        localId: 'expired',
        order: 0,
        aid: '123',
        uploadedAt: now.subtract(const Duration(days: 14)),
        cachePath: '/cache/expired.jpg',
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

      expect(first.message, '正文\n[attach]123[/attach]');
      expect(second.message, first.message);
      expect(first.imageAttachments.single.cachePath, isNull);
      expect(second.imageAttachments.single.cachePath, isNull);
      expect(second.changed, isFalse);
    });
  });
}
