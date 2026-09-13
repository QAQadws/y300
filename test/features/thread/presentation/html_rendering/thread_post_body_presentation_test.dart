import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/services/thread_image_viewport_coordinator.dart';
import 'package:y300/features/thread/presentation/services/thread_post_body_presentation.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

void main() {
  testWidgets(
    'delayed image metadata is remembered before remount and remains naturally sized',
    (tester) async {
      final dimensions = _DelayedDimensions();
      final presentation = ThreadPostBodyPresentation();
      final viewport = ThreadImageViewportCoordinator()..setActive(false);
      final sizes = <String, Size>{};
      addTearDown(presentation.dispose);
      addTearDown(viewport.dispose);
      Widget host({bool shown = true}) => ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 300,
                  child: shown
                      ? ForumHtmlWidgetPostRenderer(
                          theme: forumHtmlTestTheme,
                          sourceId: 'post',
                          threadId: '100',
                          html: '<img src="https://example.test/extra.jpg">',
                          bodyPresentation: presentation,
                          imageViewportCoordinator: viewport,
                          imageDimensionIndex: dimensions,
                          imageFallbackAspectRatioFor: (_, request) =>
                              sizes[request.cacheKey]?.aspectRatio,
                          onBlockImageResolved: (_, request, size) =>
                              sizes[request.cacheKey] = size,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
      double height() =>
          tester.getSize(find.byType(ForumHtmlWidgetPostRenderer)).height;
      await tester.pumpWidget(host());
      await tester.pump();
      final fallbackHeight = height();
      dimensions.pending.complete(
        const ForumImageDimensions(
          width: 100,
          height: 200,
          source: ForumImageDimensionSource.cacheMetadata,
        ),
      );
      await tester.pumpAndSettle();
      final measured = height();
      expect(measured, greaterThan(fallbackHeight));
      expect(sizes.values.single, const Size(100, 200));
      expect(find.byType(CachedLibraryImage), findsNothing);

      await tester.pumpWidget(host(shown: false));
      dimensions.pending = Completer<ForumImageDimensions?>();
      await tester.pumpWidget(host());
      expect(height(), closeTo(measured, 0.5));
      expect(find.byType(CachedLibraryImage), findsNothing);
      dimensions.pending.complete(
        const ForumImageDimensions(
          width: 400,
          height: 200,
          source: ForumImageDimensionSource.cacheMetadata,
        ),
      );
      await tester.pumpAndSettle();
      expect(height(), lessThan(measured)); // No permanent height lock.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'placeholder height is scoped to content, width and expansion and releases on readiness',
    (tester) async {
      final memory = ThreadPostBodyPresentation();
      addTearDown(memory.dispose);
      Widget host({
        bool shown = true,
        bool ready = true,
        double height = 80,
        double width = 300,
        String revision = 'one',
      }) => LocalizedTestApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: shown
                    ? ThreadPostBodyLayout(
                        key: ValueKey(revision),
                        presentation: memory,
                        sourceId: 'post',
                        revision: revision,
                        builder: (onReady) {
                          if (ready) onReady();
                          return SizedBox(height: ready ? height : 0);
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      double measured() =>
          tester.getSize(find.byType(ThreadPostBodyLayout)).height;
      await tester.pumpWidget(host());
      await tester.pumpWidget(host(shown: false));
      await tester.pumpWidget(host(ready: false));
      expect(measured(), 80);
      await tester.pumpWidget(host(height: 120));
      expect(measured(), 120);
      await tester.pumpWidget(host(shown: false));
      await tester.pumpWidget(host(ready: false, width: 200));
      expect(measured(), 0);
      await tester.pumpWidget(host(ready: false, revision: 'changed'));
      expect(measured(), 0);
      memory.collapseExpansion['fold'] = true;
      await tester.pumpWidget(host(ready: false));
      expect(measured(), 0);
    },
  );
}

class _DelayedDimensions implements ForumImageDimensionIndex {
  Completer<ForumImageDimensions?> pending = Completer();
  @override
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec) =>
      pending.future;
  @override
  Future<ForumImageDimensions?> getLastKnownBySpec(ForumImageLoadSpec spec) =>
      pending.future;
  @override
  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  }) async {}
}
