import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_decode_policy.dart';

void main() {
  group('LibraryCoverDecodeTarget', () {
    test('uses exact physical pixels without an application bucket', () {
      final first = LibraryCoverDecodeTarget.fromDisplaySize(
        displaySize: const Size(101, 151.5),
        devicePixelRatio: 2,
      );
      final second = LibraryCoverDecodeTarget.fromDisplaySize(
        displaySize: const Size(110, 165),
        devicePixelRatio: 2,
      );

      expect(first.targetWidthPx, 202);
      expect(first.targetHeightPx, 303);
      expect(second.targetWidthPx, 220);
      expect(second.targetHeightPx, 330);
      expect(second, isNot(first));
    });

    test('invalid or unbounded size uses a safe thumbnail fallback', () {
      final target = LibraryCoverDecodeTarget.fromDisplaySize(
        displaySize: const Size(double.infinity, 0),
        devicePixelRatio: 0,
      );

      expect(target.isOriginal, isFalse);
      expect(target.targetWidthPx, 256);
      expect(target.targetHeightPx, 384);
    });

    test('original target carries no thumbnail dimensions', () {
      const target = LibraryCoverDecodeTarget.original();

      expect(target.isOriginal, isTrue);
      expect(target.targetWidthPx, isNull);
      expect(target.targetHeightPx, isNull);
    });
  });

  group('LibraryCoverDecodePolicy', () {
    const target = LibraryCoverDecodeTarget.thumbnail(
      widthPx: 202,
      heightPx: 303,
    );

    test('preserves aspect ratio and covers the physical target', () {
      final size = LibraryCoverDecodePolicy.resolveDecodedSize(
        target: target,
        intrinsicWidth: 1200,
        intrinsicHeight: 1800,
      );

      expect(size, const Size(202, 303));
    });

    test('does not upscale a low-resolution source', () {
      final size = LibraryCoverDecodePolicy.resolveDecodedSize(
        target: target,
        intrinsicWidth: 100,
        intrinsicHeight: 150,
      );

      expect(size, const Size(100, 150));
    });

    test('caps an abnormal wide image at a 2048px long edge', () {
      final size = LibraryCoverDecodePolicy.resolveDecodedSize(
        target: const LibraryCoverDecodeTarget.thumbnail(
          widthPx: 200,
          heightPx: 300,
        ),
        intrinsicWidth: 10000,
        intrinsicHeight: 1000,
      );

      expect(size, const Size(2048, 205));
    });

    test('original and invalid intrinsic sizes request the original codec', () {
      expect(
        LibraryCoverDecodePolicy.resolveDecodedSize(
          target: const LibraryCoverDecodeTarget.original(),
          intrinsicWidth: 1200,
          intrinsicHeight: 1800,
        ),
        isNull,
      );
      expect(
        LibraryCoverDecodePolicy.resolveDecodedSize(
          target: target,
          intrinsicWidth: 0,
          intrinsicHeight: 1800,
        ),
        isNull,
      );
    });
  });
}
