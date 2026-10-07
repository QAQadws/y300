import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_restore_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const progressPolicy = NovelReaderProgressPolicy();
  const restorePolicy = NovelReaderPaginationRestorePolicy();

  final samples = <({String name, String html, bool short, bool image})>[
    (name: 'ordinary text', html: _prose(12), short: false, image: false),
    (
      name: 'short chapter',
      html: '<p>合上书后，她终于回信。</p>',
      short: true,
      image: false,
    ),
    (
      name: 'image and text',
      html:
          '${_prose(5)}'
          '<p><img src="https://example.invalid/illustration.png" '
          'width="320" height="180"></p>${_prose(5)}',
      short: false,
      image: true,
    ),
    (name: 'long chapter', html: _prose(120), short: false, image: false),
  ];

  for (final sample in samples) {
    test(
      '${sample.name}: canonical coverage and percentage are distinct',
      () async {
        final chapter = await _prepare(sample.name, sample.html);
        final original = await _paginate(chapter, height: 260);
        final reflowed = await _paginate(chapter, height: 410);
        expect(original.pages, isNotEmpty);
        expect(original.pageCount, sample.short ? 1 : greaterThan(1));
        expect(original.readableImageCount, sample.image ? 1 : 0);

        // Capture an actual page produced by the production planner, including
        // its canonical node/text identity; do not manufacture anchor ranges.
        final page = original.pages[original.pageCount ~/ 2];
        final anchor = page.startAnchor;
        expect(anchor.hasCanonicalTextOffset, isTrue);
        final saved = progressPolicy.pagedSnapshot(
          novelId: 'phase0-novel',
          episodeId: chapter.episodeId,
          flowMode: NovelReaderFlowMode.pagedLtr,
          pageIndex: page.index,
          pageCount: original.pageCount,
          paginationKey: original.key.layoutFingerprint,
          anchorNodeId: anchor.nodeId,
          anchorTextOffset: anchor.textOffset,
          anchorFormatVersion: anchor.formatVersion,
          anchorTextIdentity: anchor.textIdentity,
        );
        final sameLayout = restorePolicy.resolveInitialPage(
          plan: original,
          snapshot: saved,
        );
        expect(sameLayout.pageIndex, page.index);
        expect(sameLayout.isReadOnlyCompatibilityRestore, isFalse);

        // With no usable percentage, canonical coverage restores the actual
        // text after reflow. Existing percentage fallback remains a separate,
        // approximate contract; phase 0 does not reinterpret persisted values.
        final exactPage = reflowed.pageIndexForAnchor(
          anchor,
          isPlanComplete: true,
        );
        expect(exactPage, isNotNull);
        final exact = restorePolicy.resolveInitialPage(
          plan: reflowed,
          snapshot: saved.copyWith(isProgressPercentValid: false),
        );
        expect(exact.pageIndex, exactPage);
        expect(exact.isReadOnlyCompatibilityRestore, isFalse);

        final approximate = restorePolicy.resolveInitialPage(
          plan: reflowed,
          snapshot: saved.copyWith(
            anchorTextIdentity: 'changed-content-identity',
            progressPercent: 0.42,
            isProgressPercentValid: true,
          ),
        );
        expect(approximate.pageIndex, (0.42 * reflowed.pageCount).floor());
        expect(approximate.isReadOnlyCompatibilityRestore, isTrue);
        expect(
          progressPolicy.restoreScrollOffset(
            saved.copyWith(progressPercent: 0.42, isProgressPercentValid: true),
            maxScrollExtent: 480,
          ),
          closeTo(201.6, 0.001),
        );

        final unknown = saved.copyWith(
          paginationKey: 'unrelated-layout',
          pageIndex: original.pageCount + reflowed.pageCount + 1,
          anchorNodeId: 'removed-node',
          anchorTextIdentity: 'removed-content',
          isProgressPercentValid: false,
        );
        expect(
          restorePolicy.resolveAvailablePage(
            plan: reflowed,
            snapshot: unknown,
            isPlanComplete: false,
          ),
          isNull,
        );
        final fallback = restorePolicy.resolveInitialPage(
          plan: reflowed,
          snapshot: unknown,
        );
        expect(fallback.pageIndex, 0);
        expect(fallback.isReadOnlyCompatibilityRestore, isTrue);

        if (sample.short) {
          // A fully readable one-page chapter still stores its page start (0%).
          // Completion therefore cannot be inferred from percentage alone.
          expect(saved.progressPercent, 0);
          expect(saved.isProgressPercentValid, isTrue);
          final vertical = progressPolicy.verticalSnapshot(
            novelId: 'phase0-novel',
            episodeId: chapter.episodeId,
            scrollOffset: 0,
            maxScrollExtent: 0,
          );
          expect(vertical.progressPercent, 0);
          expect(
            progressPolicy.restoreScrollOffset(vertical, maxScrollExtent: 0),
            0,
          );
        }
      },
    );
  }

  test(
    'partial pagination preserves an anchor without inventing percentage',
    () async {
      final chapter = await _prepare('partial', _prose(20));
      final complete = await _paginate(chapter, height: 260);
      final target = complete.pages.last.startAnchor;
      final saved = progressPolicy.pagedSnapshot(
        novelId: 'phase0-novel',
        episodeId: chapter.episodeId,
        flowMode: NovelReaderFlowMode.pagedLtr,
        pageIndex: complete.pageCount - 1,
        pageCount: complete.pageCount,
        paginationKey: 'old-layout',
        isPageCountFinal: false,
        anchorNodeId: target.nodeId,
        anchorTextOffset: target.textOffset,
        anchorFormatVersion: target.formatVersion,
        anchorTextIdentity: target.textIdentity,
      );
      final prefix = NovelReaderPaginationPlan(
        key: complete.key,
        episodeId: complete.episodeId,
        pages: complete.pages.take(1).toList(),
      );
      expect(saved.pageCount, isNull);
      expect(saved.isProgressPercentValid, isFalse);
      expect(
        restorePolicy.resolveAvailablePage(
          plan: prefix,
          snapshot: saved,
          isPlanComplete: false,
        ),
        isNull,
      );
      final available = restorePolicy.resolveAvailablePage(
        plan: complete,
        snapshot: saved,
        isPlanComplete: false,
      );
      expect(available?.pageIndex, complete.pageCount - 1);
      expect(available?.isReadOnlyCompatibilityRestore, isFalse);
    },
  );
}

String _prose(int count) => List.generate(
  count,
  (index) =>
      '<p>第 $index 段：她沿着河岸走过旧书店，'
      '想起昨天没有寄出的信。等到灯亮起来，她仍然记得那句约定。</p>',
).join();

Future<NovelReaderPreparedChapter> _prepare(String name, String html) {
  final episode = NovelEpisodeItem(
    episodeId: 'phase0-$name',
    novelId: 'phase0-novel',
    sourceTid: '100',
    episodeTitle: name,
    orderIndex: 0,
  );
  return const DefaultNovelReaderHtmlPreparationService().prepare(
    rawHtml: html,
    episode: episode,
    preferences: _preferences,
    theme: _theme,
    sourceId: episode.episodeId,
    threadId: episode.sourceTid,
    imageCacheOwnerId: episode.sourceTid,
  );
}

Future<NovelReaderPaginationPlan> _paginate(
  NovelReaderPreparedChapter chapter, {
  required int height,
}) =>
    DefaultNovelReaderHybridPaginationPlanner(
      measureAdapter: const _ControlledMeasureAdapter(),
      preferences: _preferences,
      theme: _theme,
      baseStyle: const TextStyle(fontSize: 18, height: 1.5),
    ).paginate(
      chapter,
      NovelReaderPaginationKey(
        episodeId: chapter.episodeId,
        contentHash: chapter.contentHash,
        viewportWidthPx: 320,
        viewportHeightPx: height,
        typographySignature: 'phase0-18-1.5',
        themeSignature: chapter.themeSignature,
        imageDimensionRevision: chapter.imageDimensionRevision,
        rendererRevision: 20,
      ),
    );

// Text layout uses the production TextPainter path. Renderer validation and
// the one illustration use controlled geometry; this is not a device visual
// test and does not validate the future native-thread position adapter.
final class _ControlledMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const _ControlledMeasureAdapter();

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async => NovelReaderPaginationMeasureResult(
    height: request.html.contains('<img') ? 180 : 10,
  );
}

const _preferences = ForumHtmlReaderPreferences(
  typography: RichTextTypography(
    fontScale: 18 / 14,
    lineHeightScale: 1.5,
    paragraphSpacing: 12,
  ),
  conversionMode: TextConversionMode.none,
);

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Colors.white,
  foreground: Colors.black,
  link: Colors.blue,
  quoteSurface: Color(0xFFF0F0F0),
  quoteForeground: Colors.black,
  codeSurface: Color(0xFFF0F0F0),
  codeForeground: Colors.black,
);
