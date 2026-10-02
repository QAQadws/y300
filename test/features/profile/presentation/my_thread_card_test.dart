import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/cache/presentation/widgets/image_retry_placeholder.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_card.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 393.0]) {
      testWidgets(
        '$brightness at $width delays loading hints and keeps preview geometry through success, failure and retry',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final images = _ControlledImages();
          final fixtures = await _createImages(tester);
          final theme = brightness == Brightness.light
              ? AppTheme.light()
              : AppTheme.dark();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                imageCacheServiceProvider.overrideWithValue(images),
                forumImageRefererProvider.overrideWithValue(
                  'https://bbs.yamibo.com/',
                ),
              ],
              child: LocalizedTestApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.8)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: UserThreadCard(
                        item: UserThreadSummary(
                          threadId: '100',
                          title: 'A topic with independently loaded previews',
                          uri: Uri.parse(
                            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
                          ),
                          authorName: 'Author',
                          forumName: 'Forum',
                          publishedAtText: '2026-10-02',
                          excerpt: 'The preview row stays below the excerpt.',
                          views: 123,
                          replies: 8,
                          images: [
                            for (var i = 0; i < 4; i++)
                              'https://bbs.yamibo.com/preview$i.jpg',
                          ],
                        ),
                        type: UserThreadDirectoryType.threads,
                        onOpenThread: () {},
                        onOpenReply: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          // Observe the visible slots, rather than inspecting the layout widget
          // used to arrange them. Transparent reserved slots are already square.
          final initial = _previewRects(tester);
          _expectOneRow(initial);
          final initialCard = tester.getRect(find.byType(UserThreadCard));
          final keys = tester
              .widgetList<CachedLibraryImage>(find.byType(CachedLibraryImage))
              .where(
                (image) => image.request?.role == ImageCacheRole.threadInline,
              )
              .map((image) => image.request!.cacheKey)
              .toList();
          expect(keys, hasLength(3));
          expect(images.lookups.keys, containsAll(keys));
          expect(_loadingHints, findsNothing);
          expect(find.byIcon(Icons.image_outlined), findsNothing);
          expect(
            find.descendant(
              of: find.byType(CachedLibraryImage),
              matching: find.byType(ColoredBox),
            ),
            findsNothing,
          );
          await tester.pump(const Duration(milliseconds: 200));

          // First and second slots miss the disk cache; the third stays in
          // lookup. Cache misses must not restart the 300ms loading deadline.
          images.lookups[keys[0]]!.complete(null);
          images.lookups[keys[1]]!.complete(null);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 99));
          expect(_loadingHints, findsNothing);
          await tester.pump(const Duration(milliseconds: 1));
          expect(_loadingHints, findsNWidgets(3));
          _expectStable(tester, initial, initialCard);
          images.downloads[keys[0]]!.complete(
            CachedImageResult(success: true, localPath: fixtures[0].path),
          );
          await tester.pump();
          await _decodeVisibleImages(tester, expectedCount: 1);
          expect(_loadingHints, findsNWidgets(2));
          _expectStable(tester, initial, initialCard);
          await tester.pump(const Duration(milliseconds: 60));
          _expectStable(tester, initial, initialCard);

          // A failed cache write and a portrait cache hit keep their slots and
          // end their own loading hints independently of the first image.
          images.downloads[keys[1]]!.complete(CachedImageResult.failed);
          images.lookups[keys[2]]!.complete(
            CachedImageResult(
              success: true,
              fromCache: true,
              localPath: fixtures[1].path,
            ),
          );
          await tester.pump();
          await _decodeVisibleImages(tester, expectedCount: 2);
          _expectStable(tester, initial, initialCard);
          await tester.pump(const Duration(milliseconds: 60));
          _expectStable(tester, initial, initialCard);
          await tester.pumpAndSettle();
          _expectStable(tester, initial, initialCard);
          final decoded = tester.widgetList<RawImage>(find.byType(RawImage));
          expect(decoded.where((image) => image.image != null), hasLength(2));
          expect(_loadingHints, findsNothing);
          expect(find.byType(ImageRetryPlaceholder), findsOneWidget);

          images.lookups.remove(keys[1]);
          images.downloads.remove(keys[1]);
          await tester.tap(
            find.byKey(ValueKey('my-thread-image-retry-${keys[1]}')),
          );
          await tester.pump();
          expect(find.byType(ImageRetryPlaceholder), findsNothing);
          expect(_loadingHints, findsNothing);
          await tester.pump(const Duration(milliseconds: 299));
          expect(_loadingHints, findsNothing);
          await tester.pump(const Duration(milliseconds: 1));
          expect(_loadingHints, findsOneWidget);
          _expectStable(tester, initial, initialCard);
          images.lookups[keys[1]]!.complete(
            CachedImageResult(success: true, localPath: fixtures[0].path),
          );
          await tester.pump();
          await _decodeVisibleImages(tester, expectedCount: 3);
          await tester.pumpAndSettle();
          expect(_loadingHints, findsNothing);
          expect(find.byType(ImageRetryPlaceholder), findsNothing);
          _expectStable(tester, initial, initialCard);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'a fast cache hit shows its image without flashing a loading hint',
    (tester) async {
      final images = _ControlledImages();
      final fixtures = await _createImages(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageCacheServiceProvider.overrideWithValue(images)],
          child: LocalizedTestApp(
            home: Scaffold(
              body: UserThreadCard(
                item: UserThreadSummary(
                  threadId: '100',
                  title: 'Cached preview',
                  uri: Uri.parse(
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
                  ),
                  images: const ['https://bbs.yamibo.com/cached-preview.jpg'],
                ),
                type: UserThreadDirectoryType.threads,
                onOpenThread: () {},
                onOpenReply: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(_loadingHints, findsNothing);
      images.lookups.values.single.complete(
        CachedImageResult(success: true, localPath: fixtures[0].path),
      );
      await tester.pump();
      await _decodeVisibleImages(tester, expectedCount: 1);
      expect(_loadingHints, findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_loadingHints, findsNothing);
      expect(images.downloads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder get _loadingHints =>
    find.byKey(const Key('cached-library-image-loading-indicator'));

List<Rect> _previewRects(WidgetTester tester) => [
  for (final element in find.byType(CachedLibraryImage).evaluate())
    if ((element.widget as CachedLibraryImage).request?.role ==
        ImageCacheRole.threadInline)
      tester.getRect(find.byElementPredicate((value) => value == element)),
];

void _expectOneRow(List<Rect> rects) {
  expect(rects, hasLength(3));
  for (final rect in rects) {
    expect(rect.width, greaterThan(0));
    expect(rect.height, closeTo(rect.width, 0.01));
    expect(rect.top, closeTo(rects.first.top, 0.01));
  }
  for (var i = 1; i < rects.length; i++) {
    expect(rects[i].left, greaterThan(rects[i - 1].right));
  }
}

void _expectStable(WidgetTester tester, List<Rect> initial, Rect initialCard) {
  final current = _previewRects(tester);
  _expectOneRow(current);
  for (var i = 0; i < initial.length; i++) {
    expect(current[i].left, closeTo(initial[i].left, 0.01));
    expect(current[i].top, closeTo(initial[i].top, 0.01));
    expect(current[i].width, closeTo(initial[i].width, 0.01));
    expect(current[i].height, closeTo(initial[i].height, 0.01));
  }
  expect(tester.getRect(find.byType(UserThreadCard)), initialCard);
}

Future<void> _decodeVisibleImages(
  WidgetTester tester, {
  required int expectedCount,
}) async {
  // File reads and codec callbacks need real event-loop turns followed by fake
  // microtask/frame pumps. Awaiting a stream first resolved in the fake zone
  // from runAsync would leave its completion waiting for a pump indefinitely.
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    final frames = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    if (frames.length == expectedCount &&
        frames.every((frame) => frame.image != null)) {
      // First-frame observers rebuild the loading overlay on the next frame.
      await tester.pump();
      return;
    }
  }
  fail('Visible preview images did not decode.');
}

Future<List<File>> _createImages(WidgetTester tester) async {
  final directory = Directory.systemTemp.createTempSync('my_thread_preview_');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => directory.delete(recursive: true));
  });
  return (await tester.runAsync(() async {
    final files = <File>[];
    for (final size in [const Size(80, 20), const Size(20, 80)]) {
      final image = await createTestImage(
        width: size.width.toInt(),
        height: size.height.toInt(),
        cache: false,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${directory.path}/image${files.length}.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      files.add(file);
    }
    return files;
  }))!;
}

final class _ControlledImages implements ImageCacheService {
  final lookups = <String, Completer<CachedImageResult?>>{};
  final downloads = <String, Completer<CachedImageResult>>{};

  @override
  Future<CachedImageResult?> getCached(String cacheKey) =>
      lookups.putIfAbsent(cacheKey, Completer<CachedImageResult?>.new).future;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) => downloads
      .putIfAbsent(request.cacheKey, Completer<CachedImageResult>.new)
      .future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
