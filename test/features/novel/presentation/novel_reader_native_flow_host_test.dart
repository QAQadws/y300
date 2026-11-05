import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart' show ResolvedFont;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_owner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_scroll_controller.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_flow_host.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/native_reader_image_test_host.dart';

void main() {
  for (final moved in [false, true]) {
    testWidgets(
      'late long image restores visible text only without later scrolling ($moved)',
      (tester) async {
        final paragraphs = List.generate(
          12,
          (i) => '<p>Reading line number $i.</p>',
        ).join();
        final html = '<img src="https://x/late-tall.png">$paragraphs';
        final document =
            const DiscuzNovelReaderDocumentParser(captureSourceProvenance: true)
                .parse(
                  episodeId: 'chapter',
                  rawHtml: html,
                  fallbackParagraphs: const [],
                );
        final owner = NovelReaderNativeOwner();
        final scroll = NovelReaderScrollController();
        final host = NativeReaderImageTestHost(aspectRatio: 2);
        final restored = <NovelReaderTextAnchor>[];
        addTearDown(owner.dispose);
        addTearDown(scroll.dispose);
        var readyCount = 0;
        await tester.pumpWidget(
          LocalizedTestApp(
            home: Align(
              child: SizedBox(
                width: 200,
                height: 160,
                child: CustomScrollView(
                  controller: scroll,
                  slivers: [
                    NovelReaderNativeFlowHost(
                      owner: owner,
                      readingAuthority: 'read',
                      sourceId: 'chapter',
                      rawHtml: html,
                      document: document,
                      preferences: NovelReaderPreferences.defaults().copyWith(
                        flowMode: NovelReaderFlowMode.vertical,
                      ),
                      resolvedFont: ResolvedFont.system,
                      converter: const IdentityTextConverter(),
                      preparationService:
                          const DefaultNovelReaderNativePreparationService(),
                      width: 200,
                      scrollController: scroll,
                      imageHost: host,
                      imagePolicy: host,
                      threadId: null,
                      idleScheduler: () async {},
                      onContentReady: () => readyCount++,
                      onContentTerminal: () => fail('Native flow terminated'),
                      onImagesReadyChanged: (_) {},
                      onInteraction: () {},
                      onImageTap: (_) {},
                      onTextSelection: (_) {},
                      restoreReflowOffset: (offset, isCurrent) =>
                          scroll.restore(
                            (metrics) => isCurrent() ? offset : metrics.pixels,
                          ),
                      onReflowRestored: restored.add,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        Future<void> waitForReady(int count) async {
          for (var frame = 0; frame < 200 && readyCount < count; frame++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
            await tester.pump();
          }
          expect(readyCount, count);
          await tester.pumpAndSettle();
        }

        final flow = find.byType(ForumBodyFlowSliver);
        double imageHeight(ForumBodyTextPageSnapshot snapshot) => snapshot
            .expand((page) => page.fragments)
            .singleWhere((fragment) => fragment.imageFrame != null)
            .height;
        await waitForReady(1);
        final old = tester.widget<ForumBodyFlowSliver>(flow);
        final previousImage = host.callback(0);
        scroll.jumpTo(imageHeight(old.prefix) + 40);
        await tester.pumpAndSettle();
        final before = scroll.offset;
        expect(find.byType(ForumHtmlImageView), findsOneWidget);

        previousImage.resolved!(const Size(80, 640));
        if (moved) scroll.jumpTo(before + 30);
        await waitForReady(2);
        final next = tester.widget<ForumBodyFlowSliver>(flow);
        expect(imageHeight(old.prefix), 100);
        expect(imageHeight(next.prefix), 1600);
        expect(old.session.isClosed, isTrue);
        if (moved) {
          expect(restored, isEmpty);
          expect(scroll.offset, before + 30);
        } else {
          expect(restored.single.hasCanonicalTextOffset, isTrue);
          expect(scroll.offset, closeTo(before + 1500, .5));
          expect(find.byType(ForumHtmlImageView), findsNothing);
        }

        previousImage.resolved!(const Size(640, 80));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ForumBodyFlowSliver>(flow).session,
          same(next.session),
        );
        host.completeDimensions();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(owner.activeCacheHandles, 0);
      },
    );
  }

  testWidgets(
    'flow readiness follows current mounted image frames and failure',
    (tester) async {
      const html = '<p>before</p><img src="https://x/tall.png"><p>after</p>';
      final document =
          const DiscuzNovelReaderDocumentParser(captureSourceProvenance: true)
              .parse(
                episodeId: 'chapter',
                rawHtml: html,
                fallbackParagraphs: const [],
              );
      final owner = NovelReaderNativeOwner();
      final scroll = ScrollController();
      final host = NativeReaderImageTestHost(aspectRatio: .1);
      addTearDown(owner.dispose);
      addTearDown(scroll.dispose);
      final readiness = <bool>[];
      var ready = false;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Align(
            child: SizedBox(
              width: 200,
              height: 160,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  NovelReaderNativeFlowHost(
                    owner: owner,
                    readingAuthority: 'read',
                    sourceId: 'chapter',
                    rawHtml: html,
                    document: document,
                    preferences: NovelReaderPreferences.defaults().copyWith(
                      flowMode: NovelReaderFlowMode.vertical,
                    ),
                    resolvedFont: ResolvedFont.system,
                    converter: const IdentityTextConverter(),
                    preparationService:
                        const DefaultNovelReaderNativePreparationService(),
                    width: 200,
                    scrollController: scroll,
                    imageHost: host,
                    imagePolicy: host,
                    threadId: null,
                    idleScheduler: () async {},
                    onContentReady: () => ready = true,
                    onContentTerminal: () => fail('Native flow terminated'),
                    onImagesReadyChanged: readiness.add,
                    onInteraction: () {},
                    onImageTap: (_) {},
                    onTextSelection: (_) {},
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 160)),
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 150 && !ready; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(ready, isTrue);
      expect(readiness.last, isFalse);
      final first = host.callback(0);
      first.frame!();
      await tester.pumpAndSettle();
      expect(readiness.last, isTrue);
      first.failed!();
      await tester.pumpAndSettle();
      expect(readiness.last, isFalse);

      final flow = tester.widget<ForumBodyFlowSliver>(
        find.byType(ForumBodyFlowSliver),
      );
      final imageEnd = flow.prefix
          .take(2)
          .fold<double>(0, (sum, page) => sum + page.usedHeight);
      scroll.jumpTo(imageEnd);
      await tester.pumpAndSettle();
      expect(find.byType(ForumHtmlImageView), findsNothing);
      expect(readiness.last, isTrue);

      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(readiness.last, isFalse);
      first.frame!();
      await tester.pumpAndSettle();
      expect(readiness.last, isFalse);
      host.callback(0).frame!();
      await tester.pumpAndSettle();
      expect(readiness.last, isTrue);
      host.completeDimensions();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owner.activeCacheHandles, 0);
    },
  );
}
