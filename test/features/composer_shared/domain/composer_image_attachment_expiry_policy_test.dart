import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_attachment_expiry_policy.dart';

void main() {
  group('ComposerImageAttachmentExpiryPolicy', () {
    const policy = ComposerImageAttachmentExpiryPolicy();

    test('does not expire before 14 days', () {
      final uploadedAt = DateTime.utc(2026, 6, 8, 1);
      final now = uploadedAt.add(
        const Duration(days: 13, hours: 23, minutes: 59),
      );

      expect(policy.isExpired(uploadedAt: uploadedAt, now: now), isFalse);
    });

    test('expires exactly at 14 days', () {
      final uploadedAt = DateTime.utc(2026, 6, 8, 1);
      final now = uploadedAt.add(const Duration(days: 14));

      expect(policy.isExpired(uploadedAt: uploadedAt, now: now), isTrue);
    });

    test('null uploadedAt is not expired', () {
      expect(
        policy.isExpired(uploadedAt: null, now: DateTime.utc(2026, 6, 8)),
        isFalse,
      );
    });

    test('supports custom maxAge', () {
      const shortPolicy = ComposerImageAttachmentExpiryPolicy(
        maxAge: Duration(hours: 1),
      );
      final uploadedAt = DateTime.utc(2026, 6, 8, 1);

      expect(
        shortPolicy.isExpired(
          uploadedAt: uploadedAt,
          now: uploadedAt.add(const Duration(minutes: 59)),
        ),
        isFalse,
      );
      expect(
        shortPolicy.isExpired(
          uploadedAt: uploadedAt,
          now: uploadedAt.add(const Duration(hours: 1)),
        ),
        isTrue,
      );
    });
  });
}
