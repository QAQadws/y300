import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  group('ContinuousImageDiagnosticEvent', () {
    test('exports newly supported diagnostic event fields', () {
      final persisted = ContinuousImageDiagnosticEvent(
        time: DateTime(2026),
        type: ContinuousImageDiagnosticEventType.imageDimensionPersisted,
        itemId: 'image-1',
        ownerId: 'thread-1',
        index: 0,
        source: ContinuousImageSourceKind.threadPostImage.name,
        aspectRatio: 0.5,
        width: 800,
        height: 1600,
        message: 'cacheKey=abc',
      );

      expect(persisted.toLogFields(), contains('imageDimensionPersisted'));
      expect(persisted.toLogFields(), contains('size=800x1600'));
      expect(persisted.toLogFields(), contains('cacheKey=abc'));
    });

    test('keeps scroll and active image diagnostics stable', () {
      final compensated = ContinuousImageDiagnosticEvent(
        time: DateTime(2026),
        type: ContinuousImageDiagnosticEventType.scrollOffsetCompensated,
        itemId: 'page-3',
        ownerId: 'chapter-1',
        index: 3,
        message: 'delta=42.0',
      );
      final activeChanged = ContinuousImageDiagnosticEvent(
        time: DateTime(2026),
        type: ContinuousImageDiagnosticEventType.activeImageChanged,
        itemId: 'page-4',
        ownerId: 'chapter-1',
        index: 4,
      );

      expect(compensated.toLogFields(), contains('scrollOffsetCompensated'));
      expect(compensated.toLogFields(), contains('delta=42.0'));
      expect(activeChanged.toLogFields(), contains('activeImageChanged'));
    });
  });
}
