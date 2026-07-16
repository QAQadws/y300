import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/presentation/widgets/history_thumbnail.dart';

void main() {
  const resolver = HistoryThumbnailResolver();

  test(
    'prefers an existing local cover and keeps remote fallback metadata',
    () {
      final resolved = resolver.resolve(
        const HistoryThumbnailSnapshot(
          localPath: 'C:/cover.jpg',
          remoteUrl: 'https://example.com/cover.jpg',
          focusX: 0,
          focusY: 1,
        ),
        fileExists: (path) => true,
      );

      expect(resolved.localPath, 'C:/cover.jpg');
      expect(resolved.remoteUrl, 'https://example.com/cover.jpg');
      expect(resolved.alignment.x, -1);
      expect(resolved.alignment.y, 1);
    },
  );

  test('falls back to remote when local path is missing', () {
    final resolved = resolver.resolve(
      const HistoryThumbnailSnapshot(
        localPath: 'C:/missing.jpg',
        remoteUrl: 'https://example.com/cover.jpg',
      ),
      fileExists: (path) => false,
    );

    expect(resolved.localPath, isNull);
    expect(resolved.remoteUrl, 'https://example.com/cover.jpg');
    expect(resolved.hasImage, isTrue);
  });

  test('uses type icon fallback for invalid local and remote sources', () {
    final resolved = resolver.resolve(
      const HistoryThumbnailSnapshot(
        localPath: 'C:/missing.jpg',
        remoteUrl: 'file:///cover.jpg',
      ),
      fileExists: (path) => false,
    );

    expect(resolved.hasImage, isFalse);
  });

  test('rejects legacy author avatars only for thread records', () {
    const snapshot = HistoryThumbnailSnapshot(
      remoteUrl:
          'https://bbs.yamibo.com/uc_server/data/avatar/000/01/23/45_avatar_small.jpg',
    );

    final threadThumbnail = resolver.resolve(
      snapshot,
      targetType: HistoryTargetType.thread,
    );
    final comicThumbnail = resolver.resolve(
      snapshot,
      targetType: HistoryTargetType.comic,
    );

    expect(threadThumbnail.hasImage, isFalse);
    expect(comicThumbnail.remoteUrl, snapshot.remoteUrl);
  });
}
