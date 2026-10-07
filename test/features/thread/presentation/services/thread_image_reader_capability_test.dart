import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_store.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_reader_exit_result.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_capability.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  ThreadImageReaderCapability positionCapability({
    ThreadImageOpenRequest? request,
    Future<void> Function(ThreadImageReaderExitResult)? onBeforeExit,
  }) {
    final l10n = AppLocalizationsZh();
    return ThreadImageReaderCapability(
      request: request ?? _positionRequest(),
      imageReferer: null,
      title: l10n.threadImageReaderTitle,
      displayLabel: l10n.threadImageDisplay,
      downloadLabel: l10n.threadImageDownload,
      onBeforeExit: onBeforeExit,
    );
  }

  test('opening and initial viewport reports do not relocate the body', () {
    final capability = positionCapability();
    expect(capability.exitResult, isNull);
    capability.onImageVisible(1);
    capability.onScrollProgress(index: 1, offset: 0);
    expect(capability.exitResult, isNull);
    capability.noteInteraction();
    capability.onScrollProgress(index: 1, offset: 12);
    expect(capability.exitResult, isNull);
  });

  test('exit reports the current image after navigation and backtracking', () {
    final capability = positionCapability();
    capability.noteInteraction();
    capability.onScrollProgress(index: 2, offset: 500);
    capability.onScrollProgress(index: 1, offset: 300);
    // A delayed first-visibility callback must not undo backward navigation.
    capability.onImageVisible(2);
    expect(
      capability.exitResult,
      const ThreadImageReaderExitResult(
        tid: '100',
        pid: 'p1',
        indexInPost: 1,
        cacheKey: 'thread/page-1',
        url: 'https://example.com/page-1.jpg',
      ),
    );
    capability.onScrollProgress(index: 0, offset: 0);
    expect(capability.exitResult, isNull);
  });

  test('invalid indexes do not replace the last reported image', () {
    final capability = positionCapability();
    capability.noteInteraction();
    capability.onScrollProgress(index: 1, offset: 300);
    capability.onScrollProgress(index: -1, offset: 0);
    capability.onScrollProgress(index: 99, offset: 0);
    expect(capability.exitResult?.indexInPost, 1);
  });

  test('seek reports its confirmed destination', () async {
    final capability = positionCapability();
    capability.noteInteraction();
    await capability.onSeek(index: 2, offset: 600);
    expect(capability.exitResult?.indexInPost, 2);
  });

  test(
    'explicit seek confirms an image already reported by initial layout',
    () async {
      final capability = positionCapability();
      capability.onScrollProgress(index: 1, offset: 0);
      expect(capability.exitResult, isNull);
      await capability.onSeek(index: 1, offset: 0);
      expect(capability.exitResult?.indexInPost, 1);
    },
  );

  test('inconsistent opening identity returns no relocation', () {
    final request = _positionRequest();
    final capability = positionCapability(
      request: ThreadImageOpenRequest(
        tid: request.tid,
        pid: request.pid,
        postNumber: request.postNumber,
        referer: request.referer,
        group: ThreadPostImageGroup(
          tid: request.tid,
          pid: 'other-post',
          postNumber: request.postNumber,
          entries: request.group.entries,
        ),
        initialIndex: request.initialIndex,
        continuousImages: request.continuousImages,
      ),
    );
    capability.noteInteraction();
    capability.onScrollProgress(index: 2, offset: 600);
    expect(capability.exitResult, isNull);
  });

  test('mismatched image mapping returns no relocation', () {
    final request = _positionRequest();
    final entries = request.group.entries.toList();
    entries[1] = const ThreadPostImageEntry(
      url: 'https://example.com/replaced.jpg',
      rawUrl: 'https://example.com/replaced.jpg',
      indexInPost: 1,
      cacheKey: 'different-cache-key',
    );
    final capability = positionCapability(
      request: ThreadImageOpenRequest(
        tid: request.tid,
        pid: request.pid,
        postNumber: request.postNumber,
        referer: request.referer,
        group: ThreadPostImageGroup(
          tid: request.tid,
          pid: request.pid,
          postNumber: request.postNumber,
          entries: entries,
        ),
        initialIndex: request.initialIndex,
        continuousImages: request.continuousImages,
      ),
    );
    capability.noteInteraction();
    capability.onScrollProgress(index: 1, offset: 300);
    expect(capability.exitResult, isNull);
  });

  test('exit freezes position and prepares the body only once', () async {
    final gate = Completer<void>();
    final received = <ThreadImageReaderExitResult>[];
    final capability = positionCapability(
      onBeforeExit: (result) async {
        received.add(result);
        await gate.future;
      },
    );
    capability.noteInteraction();
    capability.onScrollProgress(index: 1, offset: 300);
    final first = capability.onExit();
    final second = capability.onExit();
    expect(identical(first, second), isTrue);
    capability.onScrollProgress(index: 2, offset: 600);
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    expect(received.single.indexInPost, 1);
    expect(capability.exitResult?.indexInPost, 1);
    gate.complete();
    await first;
    await capability.onExit();
    expect(received, hasLength(1));
  });

  test(
    'retired binding rejects progress and does not prepare a return',
    () async {
      var calls = 0;
      final capability = positionCapability(onBeforeExit: (_) async => calls++);
      capability.noteInteraction();
      capability.onScrollProgress(index: 1, offset: 300);
      capability.retire();
      capability.onScrollProgress(index: 2, offset: 600);
      await capability.onExit();
      expect(capability.exitResult, isNull);
      expect(calls, 0);
    },
  );

  test(
    'retiring before the exit microtask prevents stale preparation',
    () async {
      var calls = 0;
      final capability = positionCapability(onBeforeExit: (_) async => calls++);
      capability.noteInteraction();
      capability.onScrollProgress(index: 1, offset: 300);
      final exit = capability.onExit();
      capability.retire();
      await exit;
      expect(calls, 0);
      expect(capability.exitResult, isNull);
    },
  );

  test('failed optional return preparation still completes exit', () async {
    final capability = positionCapability(
      onBeforeExit: (_) async => throw StateError('return layout unavailable'),
    );
    capability.noteInteraction();
    capability.onScrollProgress(index: 1, offset: 300);
    await capability.onExit();
    expect(capability.exitResult?.indexInPost, 1);
  });

  const item = ContinuousImageItem(
    ownerId: 'thread:573279:post:8899',
    id: 'thread-image-0',
    url: 'https://example.com/forum/page-1.jpg',
    cacheKey: 'thread-image-cache-key',
    index: 0,
    sourceKind: ContinuousImageSourceKind.threadImageReader,
  );

  ThreadImageReaderCapability buildCapability() {
    final l10n = AppLocalizationsZh();
    return ThreadImageReaderCapability(
      request: const ThreadImageOpenRequest(
        tid: '573279',
        pid: '8899',
        postNumber: 1,
        referer: 'https://example.com/thread-573279.htm',
        group: ThreadPostImageGroup(
          tid: '573279',
          pid: '8899',
          postNumber: 1,
          entries: [],
        ),
        initialIndex: 0,
        continuousImages: [item],
      ),
      imageReferer: null,
      title: l10n.threadImageReaderTitle,
      displayLabel: l10n.threadImageDisplay,
      downloadLabel: l10n.threadImageDownload,
    );
  }

  /// 直接渲染能力交出的 errorPlaceholder，不依赖真实网络失败。
  Future<void> pumpErrorPlaceholder(
    WidgetTester tester, {
    required bool paged,
    required VoidCallback onRetry,
  }) async {
    final store = ReaderImageSessionStore();
    addTearDown(store.dispose);
    store.startSession(
      readerOwnerId: item.ownerId,
      generation: 1,
      items: const [item],
    );
    final capability = buildCapability();

    late Widget content;
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                content = capability.buildImageContent(
                  context,
                  ReaderImageBuildSpec(
                    item: item,
                    index: 0,
                    paged: paged,
                    fit: BoxFit.contain,
                    sessionBinding: store.bindingFor(item),
                    expectedDisplaySize: const Size(320, 480),
                    loadingIndicatorColor: Colors.white,
                    onDimensionsResolved: (_) {},
                    onRetry: onRetry,
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    final sessionImage = content as ReaderSessionImage;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(body: Center(child: sessionImage.errorPlaceholder)),
      ),
    );
  }

  for (final paged in <bool>[true, false]) {
    final mode = paged ? 'paged' : 'continuous';
    testWidgets('$mode error placeholder retries through the engine callback', (
      tester,
    ) async {
      var retryCount = 0;
      await pumpErrorPlaceholder(
        tester,
        paged: paged,
        onRetry: () => retryCount += 1,
      );

      final retryButton = find.byKey(
        const ValueKey<String>('thread-image-reader-retry-thread-image-0'),
      );
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pump();

      expect(retryCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('error placeholder does not impose its own aspect ratio', (
    tester,
  ) async {
    // 竖向连续模式的高度由外层 slot 预留；占位自带比例会顶掉预留值，导致滑块
    // seek 落偏（回归见 thread_image_reader_page_test 的 exact item anchor）。
    await pumpErrorPlaceholder(tester, paged: false, onRetry: () {});

    expect(find.byType(AspectRatio), findsNothing);
  });
}

ThreadImageOpenRequest _positionRequest() {
  final entries = List<ThreadPostImageEntry>.generate(
    3,
    (index) => ThreadPostImageEntry(
      url: 'https://example.com/page-$index.jpg',
      rawUrl: 'https://example.com/page-$index.jpg',
      indexInPost: index,
      cacheKey: 'thread/page-$index',
    ),
  );
  return ThreadImageOpenRequest(
    tid: '100',
    pid: 'p1',
    postNumber: 1,
    referer: 'https://example.com/thread-100.html',
    group: ThreadPostImageGroup(
      tid: '100',
      pid: 'p1',
      postNumber: 1,
      entries: entries,
    ),
    initialIndex: 0,
    continuousImages: List.generate(
      entries.length,
      (index) => ContinuousImageItem(
        ownerId: 'thread:100:post:p1',
        id: 'image-$index',
        url: entries[index].url,
        cacheKey: entries[index].cacheKey,
        index: index,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
      ),
    ),
  );
}
