import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_store.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_capability.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
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
      request: ThreadImageOpenRequest(
        tid: '573279',
        pid: '8899',
        postNumber: 1,
        referer: 'https://example.com/thread-573279.htm',
        group: const ThreadPostImageGroup(
          tid: '573279',
          pid: '8899',
          postNumber: 1,
          entries: [],
        ),
        initialIndex: 0,
        continuousImages: const [item],
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
