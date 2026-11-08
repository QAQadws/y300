import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/thread/presentation/widgets/thread_poll_option_image.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'image geometry survives loading, dimension recording and lazy recycling',
    (tester) async {
      final file = await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'y300-poll-image-',
        );
        final image = await createTestImage(
          width: 60,
          height: 120,
          cache: false,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = await File('${directory.path}/image.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        addTearDown(() async {
          await file.delete();
          await directory.delete();
        });
        return file;
      });
      final cache = _Cache();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final theme = AppTheme.light();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageCacheServiceProvider.overrideWithValue(cache)],
          child: LocalizedTestApp(
            theme: theme,
            home: Scaffold(
              body: ListView.builder(
                controller: scroll,
                addAutomaticKeepAlives: false,
                itemCount: 30,
                itemBuilder: (_, index) => index == 0
                    ? ThreadPollCard(
                        poll: _poll,
                        imageOwnerId: '100',
                        imageReferer:
                            'https://example.test/thread-100-1-1.html',
                        selectedOptionIds: const {},
                        isSubmitting: false,
                        commandAvailable: true,
                        hint: null,
                        palette: ThreadDetailNativePalette.resolve(theme),
                        onToggleOption: (_) {},
                        onSubmit: () {},
                      )
                    : const SizedBox(height: 300),
              ),
            ),
          ),
        ),
      );
      final tile = find.byKey(const Key('thread-poll-option-1'));
      final before = tester.getSize(tile);
      final firstState = tester.state(find.byType(ThreadPollOptionImageView));
      expect(
        tester.getSize(find.byType(ThreadPollOptionImageView)),
        const Size.square(96),
      );
      final request = tester
          .widget<CachedLibraryImage>(find.byType(CachedLibraryImage))
          .request!;
      expect(request.ownerId, '100');
      expect(request.referer, 'https://example.test/thread-100-1-1.html');
      cache.complete(
        CachedImageResult(
          success: true,
          cacheKey: request.cacheKey,
          localPath: file!.path,
        ),
      );
      await tester.pump();
      // Decode and the shared asynchronous encoded-size probe run outside the
      // fake test clock. No production image provider or cache path is replaced.
      for (var i = 0; i < 20 && !cache.recorded.isCompleted; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(cache.sizes[request.cacheKey], const Size(60, 120));
      final resolved = tester.widget<CachedLibraryImage>(
        find.byType(CachedLibraryImage),
      );
      expect(resolved.decodeDisplaySize, const Size(48, 96));
      expect(resolved.fit, BoxFit.contain);
      expect(tester.getSize(tile), before);
      expect(find.text('图文选项'), findsOneWidget);
      scroll.jumpTo(5000);
      await tester.pump();
      expect(firstState.mounted, isFalse);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(tile), before);
      expect(cache.reads, greaterThan(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed image keeps the same slot and a selectable label at large text sizes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = _Cache();
      var toggles = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageCacheServiceProvider.overrideWithValue(cache)],
          child: LocalizedTestApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ThreadPollCard(
                poll: _poll,
                selectedOptionIds: const {},
                isSubmitting: false,
                commandAvailable: true,
                hint: null,
                palette: ThreadDetailNativePalette.resolve(AppTheme.light()),
                onToggleOption: (_) => toggles++,
                onSubmit: () {},
              ),
            ),
          ),
        ),
      );
      final tile = find.byKey(const Key('thread-poll-option-1'));
      final before = tester.getSize(tile);
      cache.complete(null);
      await tester.pumpAndSettle();
      expect(tester.getSize(tile), before);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      await tester.tap(find.text('图文选项'));
      expect(toggles, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

const _poll = ThreadPoll(
  isMultipleChoice: false,
  summary: '',
  options: [
    ThreadPollOption(
      id: '1',
      label: '图文选项',
      image: ThreadPollOptionImage(
        url: 'https://example.test/poll.png',
        alt: 'sample.png',
      ),
      percent: 50,
      voteCount: 1,
    ),
    ThreadPollOption(id: '2', label: '文字选项'),
  ],
);

class _Cache extends ImageCacheService implements ImageCacheDimensionRecorder {
  final lookup = Completer<CachedImageResult?>();
  final recorded = Completer<void>();
  final sizes = <String, Size>{};
  CachedImageResult? result;
  int reads = 0;

  void complete(CachedImageResult? value) {
    result = value;
    lookup.complete(value);
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    reads++;
    await lookup.future;
    final size = sizes[cacheKey];
    return size == null
        ? result
        : CachedImageResult(
            success: true,
            cacheKey: cacheKey,
            localPath: result!.localPath,
            width: size.width.toInt(),
            height: size.height.toInt(),
          );
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      CachedImageResult.failed;
  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async => CachedImageResult.failed;
  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;
  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
  @override
  Future<void> clearUnprotected() async {}
  @override
  Future<void> recordResolvedDimensions({
    required String cacheKey,
    required Size size,
  }) async {
    sizes[cacheKey] = size;
    if (!recorded.isCompleted) recorded.complete();
  }
}
