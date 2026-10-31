import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/presentation/widgets/history_thumbnail.dart';

import '../test_support/history_test_support.dart';

void main() {
  const resolver = HistoryThumbnailResolver();

  testWidgets('a missing local cover keeps the type icon fallback', (
    tester,
  ) async {
    final previousOverrides = io.IOOverrides.current;
    io.IOOverrides.global = _MissingThumbnailFileOverrides();
    addTearDown(() => io.IOOverrides.global = previousOverrides);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: HistoryThumbnail(
            entry: historyEntry(
              type: HistoryTargetType.comic,
              id: '1',
              title: 'Comic',
              visitedAt: DateTime.utc(2026, 10, 31),
              thumbnail: const HistoryThumbnailSnapshot(
                localPath: 'missing-cover.jpg',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  test('preserves the local cover candidate and remote fallback metadata', () {
    final resolved = resolver.resolve(
      const HistoryThumbnailSnapshot(
        localPath: 'C:/cover.jpg',
        remoteUrl: 'https://example.com/cover.jpg',
        focusX: 0,
        focusY: 1,
      ),
    );

    expect(resolved.localPath, 'C:/cover.jpg');
    expect(resolved.remoteUrl, 'https://example.com/cover.jpg');
    expect(resolved.alignment.x, -1);
    expect(resolved.alignment.y, 1);
  });

  test('normalizes local candidates without accessing the filesystem', () {
    final resolved = io.IOOverrides.runZoned(
      () => resolver.resolve(
        const HistoryThumbnailSnapshot(
          localPath: ' C:/missing.jpg ',
          remoteUrl: 'https://example.com/cover.jpg',
        ),
      ),
      createFile: (_) =>
          throw StateError('Thumbnail projection must not do I/O'),
    );

    expect(resolved.localPath, 'C:/missing.jpg');
    expect(resolved.remoteUrl, 'https://example.com/cover.jpg');
    expect(resolved.hasImage, isTrue);
  });

  test('uses type icon fallback for invalid local and remote sources', () {
    final resolved = resolver.resolve(
      const HistoryThumbnailSnapshot(
        localPath: ' ',
        remoteUrl: 'file:///cover.jpg',
      ),
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

final class _MissingThumbnailFileOverrides extends io.IOOverrides {
  @override
  io.File createFile(String path) => _MissingThumbnailFile(path);
}

class _MissingThumbnailFile extends Fake implements io.File {
  _MissingThumbnailFile(this.path);

  @override
  final String path;

  @override
  Future<int> length() => Future<int>.error(
    io.PathNotFoundException(path, const io.OSError('missing', 2)),
  );

  @override
  Future<bool> exists() async => false;

  @override
  bool existsSync() => throw StateError('Synchronous thumbnail file check');
}
