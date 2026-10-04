import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

void main() {
  testWidgets('dimension lookup failure leaves the displayed fallback intact', (
    tester,
  ) async {
    final dimensions = _Dimensions(deferred: true);
    final host = _ImageHost(dimensions);
    final resolved = <Size>[];
    await tester.pumpWidget(_host(host, onResolved: resolved.add));
    await tester.pump();

    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      0.7,
    );
    dimensions.pending.single.completeError(StateError('metadata unavailable'));
    await tester.pump();

    expect(find.byType(_DisplayedImage), findsOneWidget);
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      0.7,
    );
    expect(resolved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dimension lookup completing after unmount cannot report a size',
    (tester) async {
      final dimensions = _Dimensions(deferred: true);
      final host = _ImageHost(dimensions);
      final resolved = <Size>[];
      await tester.pumpWidget(_host(host, onResolved: resolved.add));
      await tester.pump();
      expect(dimensions.pending, hasLength(1));
      await tester.pumpWidget(_host(host, shown: false));
      dimensions.pending.single.complete(
        const ForumImageDimensions(
          width: 100,
          height: 200,
          source: ForumImageDimensionSource.cacheMetadata,
        ),
      );
      await tester.pump();

      expect(find.byType(_DisplayedImage), findsNothing);
      expect(resolved, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failed in [false, true]) {
    testWidgets(
      '${failed ? 'failure' : 'first frame'} releases another visible image',
      (tester) async {
        final host = _ImageHost(_Dimensions());
        final viewport = ForumHtmlImageViewportCoordinator(
          maxVisibleFirstFrames: 1,
        );
        addTearDown(viewport.dispose);
        await tester.pumpWidget(
          _host(host, viewport: viewport, imageCount: 3, height: 450),
        );
        await _frames(tester);
        expect(find.byType(_DisplayedImage), findsOneWidget);
        final first = tester.widget<_DisplayedImage>(
          find.byType(_DisplayedImage),
        );

        if (failed) {
          expect(first.onFailed, isNotNull);
          first.onFailed!();
        } else {
          expect(first.onFirstFrame, isNotNull);
          first.onFirstFrame!();
        }
        await _frames(tester);

        final displayed = tester.widgetList<_DisplayedImage>(
          find.byType(_DisplayedImage),
        );
        expect(displayed, hasLength(2));
        expect(displayed.map((image) => image.url).toSet(), hasLength(2));
        expect(displayed.map((image) => image.url), contains(first.url));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final unmount in [false, true]) {
    testWidgets(
      'scoped disk prefetch is cancelled when ${unmount ? 'unmounted' : 'inactive'}',
      (tester) async {
        final host = _ImageHost(_Dimensions());
        final viewport = ForumHtmlImageViewportCoordinator(
          maxVisibleFirstFrames: 1,
          prefetchExtentFactor: 2,
        );
        final precache = _DiskPrecache();
        addTearDown(viewport.dispose);
        Widget build({bool shown = true}) => _host(
          host,
          shown: shown,
          viewport: viewport,
          precache: precache,
          imageCount: 3,
          height: 150,
        );
        await tester.pumpWidget(build());
        await _frames(tester);
        expect(precache.work, isEmpty);
        tester
            .widget<_DisplayedImage>(find.byType(_DisplayedImage))
            .onFirstFrame!();
        await _frames(tester);
        expect(precache.work, hasLength(1));
        final old = precache.work.single;
        expect(old.scope.isActive, isTrue);

        if (unmount) {
          await tester.pumpWidget(build(shown: false));
        } else {
          viewport.setActive(false);
          await _frames(tester);
        }
        expect(old.scope.isActive, isFalse);
        expect(find.byType(_DisplayedImage), findsNothing);
        old.complete();
        await _frames(tester);
        expect(precache.work, hasLength(1));
        expect(find.byType(_DisplayedImage), findsNothing);

        if (!unmount) {
          viewport.setActive(true);
          await _frames(tester);
          tester
              .widget<_DisplayedImage>(find.byType(_DisplayedImage))
              .onFirstFrame!();
          await _frames(tester);
          expect(precache.work, hasLength(2));
          final current = precache.work.last;
          expect(current.scope, isNot(same(old.scope)));
          expect(current.scope.isActive, isTrue);
          current.complete();
        } else {
          expect(viewport.registeredImageCount, 0);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump();
  }
}

Widget _host(
  _ImageHost host, {
  bool shown = true,
  ForumHtmlImageViewportCoordinator? viewport,
  ForumImagePrecacheService? precache,
  int imageCount = 1,
  double height = 300,
  ValueChanged<Size>? onResolved,
}) => ProviderScope(
  overrides: [forumHtmlImageHostProvider.overrideWithValue(host)],
  child: LocalizedTestApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          height: height,
          child: SingleChildScrollView(
            child: shown
                ? ForumHtmlWidgetPostRenderer(
                    theme: forumHtmlTestTheme,
                    sourceId: 'host-lifecycle',
                    threadId: '100',
                    buildAsync: false,
                    enableCaching: false,
                    html: [
                      for (var image = 0; image < imageCount; image++)
                        '<div><img src="https://example.invalid/$image.jpg" '
                            '${viewport == null ? '' : 'width="200" height="200"'}></div>',
                    ].join(),
                    imageViewportCoordinator: viewport,
                    imagePrecacheService: precache,
                    onBlockImageResolved: (_, _, size) =>
                        onResolved?.call(size),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  ),
);

final class _Dimensions implements ForumImageDimensionIndex {
  _Dimensions({this.deferred = false});

  final bool deferred;
  final pending = <Completer<ForumImageDimensions?>>[];

  @override
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec) {
    if (!deferred) return Future.value(null);
    final result = Completer<ForumImageDimensions?>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<ForumImageDimensions?> getLastKnownBySpec(ForumImageLoadSpec spec) =>
      getBySpec(spec);

  @override
  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  }) async {}
}

final class _ImageHost implements ForumHtmlImageHost {
  const _ImageHost(this.dimensionIndex);

  @override
  final ForumImageDimensionIndex dimensionIndex;

  @override
  Widget buildCachedImage({
    required ImageCacheRequest request,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    String? referer,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) => _DisplayedImage(
    url: request.sourceUrl,
    onFirstFrame: onFirstFrameRendered,
    onFailed: onImageFailed,
  );
}

final class _DisplayedImage extends StatelessWidget {
  const _DisplayedImage({
    required this.url,
    required this.onFirstFrame,
    required this.onFailed,
  });

  final String url;
  final VoidCallback? onFirstFrame;
  final VoidCallback? onFailed;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

final class _DiskWork {
  _DiskWork(this.scope);

  final ForumImageWorkScope scope;
  final result = Completer<ForumImagePrecacheResult>();

  void complete() => result.complete(
    const ForumImagePrecacheResult(success: true, diskCacheAttempted: true),
  );
}

final class _DiskPrecache
    implements ForumImagePrecacheService, ScopedForumImagePrecacheService {
  final work = <_DiskWork>[];

  @override
  Future<ForumImagePrecacheResult> ensureDiskCachedScoped(
    ForumImageLoadSpec spec, {
    required ForumImageWorkScope scope,
  }) {
    final request = _DiskWork(scope);
    work.add(request);
    return request.result.future;
  }

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(ForumImageLoadSpec spec) =>
      throw StateError('The renderer must pass its lifecycle scope.');

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) => throw StateError('HTML look-ahead must only warm disk cache.');

  @override
  Future<ForumImagePrecacheResult> precacheDecodedScoped({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    required ForumImageWorkScope scope,
    Size? expectedDisplaySize,
  }) => throw StateError('HTML look-ahead must only warm disk cache.');
}
