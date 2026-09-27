import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/presentation/widgets/history_thumbnail.dart';

import '../test_support/history_test_support.dart';

void main() {
  const resolver = HistoryThumbnailResolver();

  testWidgets('uses a journal icon when a blog has no body image', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryThumbnail(
          entry: historyEntry(
            type: HistoryTargetType.blog,
            id: '101:23',
            title: '日志',
            visitedAt: DateTime.utc(2026, 9, 27),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('history-thumbnail-fallback-blog')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

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
