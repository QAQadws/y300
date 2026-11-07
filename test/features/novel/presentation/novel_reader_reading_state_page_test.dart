import '../../../../tool/legacy/content_rendering.dart';
import '../../../../tool/legacy/novel/legacy_preparation_provider.dart';
import '../../../../tool/legacy/novel/legacy_reader_surface.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/preferences/novel_chapter_interactions_dock_preferences_provider.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_spacing.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import '../../../../tool/legacy/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_page_coverage.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_source_location.dart';
import '../../../../tool/legacy/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reading_body_sliver.dart';
import '../../../../tool/legacy/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import '../../../../tool/legacy/novel/presentation/widgets/novel_reader_html_document_view.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_flow_host.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_surface.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_position_bookmarks_dialog.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';

const _work = 'novel:49:100';
const _chapter = 'novel:49:100:5001';
const _next = 'novel:49:100:5002';
const _args = NovelReaderArgs(novelId: _work, episodeId: _chapter);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final (bodyKind, roundTrip) in const [
    ('text', false),
    ('text', true),
    ('table', false),
    ('table', true),
    ('floated table', true),
  ]) {
    testWidgets(
      'mode change uses the visible source ($bodyKind, round trip: $roundTrip)',
      (tester) async {
        final table = bodyKind != 'text';
        final floated = bodyKind == 'floated table';
        final rows = List.generate(
          18,
          (i) =>
              '<tr height="88"><td width="850">左列 $i</td>'
              '<td width="810">右列 $i，继续阅读同一个格子的文字。</td></tr>',
        ).join();
        final markup = '<table width="1660" cellpadding="0">$rows</table>';
        final repository = _ReadingRepository(switch (bodyKind) {
          'floated table' =>
            '<p>表格前</p><span style="float:right;width:300px;margin-left:5px">'
                '浮动内表前。$markup浮动内表后。</span>'
                '表旁文字<br style="clear:both">$_nativeLongBody',
          'table' => '<p>表格前</p>$markup$_nativeLongBody',
          _ => _nativeLongBody,
        });
        final saved = NovelReadingProgress(
          novelId: _work,
          episodeId: _chapter,
          scrollOffset: 0,
          updatedAt: DateTime(2026, 10, 1),
        );
        repository.progress[_chapter] = saved;
        repository.recent = _chapter;
        await tester.pumpWidget(
          _app(
            repository,
            nativePagination: true,
            preferences: NovelReaderPreferences.defaults().copyWith(
              flowMode: NovelReaderFlowMode.vertical,
            ),
          ),
        );
        final flow = find.byType(ForumBodyFlowSliver);
        for (var frame = 0; frame < 200; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump();
          if (flow.evaluate().isNotEmpty &&
              tester
                  .renderObject<RenderForumBodyFlowBoundary>(flow)
                  .finalBoundaryKnown) {
            break;
          }
        }
        await tester.pumpAndSettle();
        final host = tester.widget<NovelReaderNativeFlowHost>(
          find.byType(NovelReaderNativeFlowHost),
        );
        final outer = host.scrollController;
        outer.jumpTo(table ? 450 : outer.position.maxScrollExtent * .45);
        await tester.pumpAndSettle();
        if (table) {
          if (floated) {
            final page = tester
                .widget<ForumBodyFlowSliver>(flow)
                .prefix
                .singleWhere((page) => page.floatedTables.isNotEmpty);
            expect(page.floatedTables.single.bounds.width, 300);
            expect(page.fragments.first.width, lessThan(500));
          }
          tester
              .widget<ForumBodyTableFlowViewport>(
                find.byType(ForumBodyTableFlowViewport),
              )
              .horizontalController
              .jumpTo(820);
          await tester.pumpAndSettle();
        }
        final token = NovelReaderPaginationCancellationToken();
        addTearDown(token.cancel);
        NovelReaderTextAnchor? expected;
        final state = (host.key! as GlobalKey<NovelReaderNativeFlowHostState>)
            .currentState!;
        unawaited(
          state
              .captureVisibleSource(token)
              .then((source) => expected = source?.anchor),
        );
        for (var frame = 0; frame < 50 && expected == null; frame++) {
          await tester.pump();
        }
        expect(expected?.hasCanonicalTextOffset, isTrue);
        expect(repository.progress[_chapter], same(saved));

        await _changeModeViaDisplaySettings(
          tester,
          NovelReaderFlowMode.pagedLtr,
        );
        await _pumpNativeReady(tester, advanceTime: true);

        final surface = tester.widget<NovelReaderNativePagedSurface>(
          find.byType(NovelReaderNativePagedSurface),
        );
        final controller = _nativeController(tester);
        expect(surface.owner, same(host.owner));
        expect(surface.conversionAnchor?.nodeId, expected!.nodeId);
        expect(surface.conversionAnchor?.textOffset, expected!.textOffset);
        expect(controller.visiblePageIndex, greaterThan(0));
        if (table) {
          final book = tester.widget<ForumBodyTableBookViewport>(
            find.byType(ForumBodyTableBookViewport),
          );
          final horizontal = book.horizontalController.position;
          final vertical = book.verticalController.position;
          expect(horizontal.pixels, greaterThan(400));
          expect(
            horizontal.pixels + horizontal.viewportDimension,
            greaterThan(850),
          );
          expect(vertical.pixels, greaterThan(100));
          expect(
            vertical.pixels + vertical.viewportDimension,
            greaterThan(450),
          );
        } else {
          expect(controller.visibleView!.coverage.locate(expected!), isNotNull);
        }
        expect(repository.progress[_chapter], same(saved));
        expect(repository.committed, isEmpty);
        expect(repository.completed, isEmpty);

        if (roundTrip) {
          await _changeModeViaDisplaySettings(
            tester,
            NovelReaderFlowMode.vertical,
          );
          final flowHost = find.byType(NovelReaderNativeFlowHost);
          for (var frame = 0; frame < 250; frame++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
            await tester.pump(const Duration(milliseconds: 16));
            if (flow.evaluate().isNotEmpty &&
                tester.widget<ForumBodyFlowSliver>(flow).prefix.isComplete &&
                _verticalPosition(tester).pixels > 0) {
              break;
            }
          }
          await tester.pumpAndSettle();
          final returned = tester.widget<NovelReaderNativeFlowHost>(flowHost);
          final returnedState =
              (returned.key! as GlobalKey<NovelReaderNativeFlowHostState>)
                  .currentState!;
          NovelReaderTextAnchor? actual;
          unawaited(
            returnedState
                .captureVisibleSource(token)
                .then((source) => actual = source?.anchor),
          );
          for (var frame = 0; frame < 50 && actual == null; frame++) {
            await tester.pump();
          }
          expect(returned.owner, same(host.owner));
          expect(controller.isClosed, isTrue);
          expect(actual?.nodeId, expected!.nodeId);
          expect(actual?.textOffset, expected!.textOffset);
          if (table) {
            final viewport = tester.widget<ForumBodyTableFlowViewport>(
              find.byType(ForumBodyTableFlowViewport),
            );
            expect(viewport.horizontalController.offset, greaterThan(800));
            expect(_verticalPosition(tester).pixels, closeTo(450, 88));
          }
          expect(repository.progress[_chapter], same(saved));
          expect(repository.committed, isEmpty);
          expect(repository.completed, isEmpty);
        } else {
          final page = controller.visiblePageIndex!;
          if (table) {
            surface.navigationController!.turnNext();
          } else {
            await tester.tapAt(const Offset(744, 300));
          }
          await _pumpNativeReady(tester, page: page + 1, advanceTime: true);
          await tester.pump(const Duration(milliseconds: 350));
          expect(repository.progress[_chapter]!.pageIndex, page + 1);
          expect(repository.progress[_chapter]!.anchorFormatVersion, 1);
          expect(controller.isClosed, isFalse);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(host.owner.isClosed, isTrue);
        expect(host.owner.activeCacheHandles, 0);
      },
    );
  }

  testWidgets('the second duplicate long image keeps its position across modes', (
    tester,
  ) async {
    final image = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'y300-mode-image-',
      );
      final image = File('${directory.path}/image.png');
      addTearDown(() async {
        if (await image.exists()) await image.delete();
        await directory.delete();
      });
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 24, 192),
        Paint()..color = Colors.blue,
      );
      final picture = recorder.endRecording();
      final pixels = await picture.toImage(24, 192);
      final data = (await pixels.toByteData(format: ui.ImageByteFormat.png))!;
      pixels.dispose();
      picture.dispose();
      return image.writeAsBytes(data.buffer.asUint8List());
    });
    const slot =
        '<img src="https://bbs.yamibo.com/data/attachment/forum/mode.png" width="24" height="192">';
    final repository = _ReadingRepository('$slot$slot');
    final saved = NovelReadingProgress(
      novelId: _work,
      episodeId: _chapter,
      scrollOffset: 0,
      updatedAt: DateTime(2026),
    );
    repository.progress[_chapter] = saved;
    repository.recent = _chapter;
    await tester.pumpWidget(
      _app(
        repository,
        nativePagination: true,
        images: _CachedModeImage(image!),
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.vertical,
        ),
      ),
    );
    final body = find.byType(ForumBodyFlowSliver);
    for (var frame = 0; frame < 250; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
      if (body.evaluate().isNotEmpty &&
          tester.widget<ForumBodyFlowSliver>(body).prefix.isComplete) {
        break;
      }
    }
    Future<NovelReaderNativeSourceLocation> capture() async {
      final host = tester.widget<NovelReaderNativeFlowHost>(
        find.byType(NovelReaderNativeFlowHost),
      );
      final state = (host.key! as GlobalKey<NovelReaderNativeFlowHostState>)
          .currentState!;
      final token = NovelReaderPaginationCancellationToken();
      NovelReaderNativeSourceLocation? source;
      try {
        for (var frame = 0; frame < 250 && source == null; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump();
          var finished = false;
          unawaited(
            state.captureVisibleSource(token).then((value) {
              source = value;
              finished = true;
            }),
          );
          for (var step = 0; step < 50 && !finished; step++) {
            await tester.pump();
          }
          expect(finished, isTrue);
        }
        expect(source, isNotNull);
        return source!;
      } finally {
        token.cancel();
      }
    }

    final beginning = await capture();
    await tester.pumpAndSettle();
    final prefix = tester.widget<ForumBodyFlowSliver>(body).prefix;
    expect(prefix, hasLength(2));
    expect(prefix.last.usedHeight, greaterThan(1024));
    final originalY = prefix.first.usedHeight + prefix.last.usedHeight * .4;
    _verticalPosition(tester).jumpTo(originalY);
    final original = await capture();
    expect(original.anchor.nodeId, isNot(beginning.anchor.nodeId));
    expect(original.imageProgress, closeTo(.4, .02));
    await _changeModeViaDisplaySettings(tester, NovelReaderFlowMode.pagedLtr);
    await _pumpNativeReady(tester, page: 1, advanceTime: true);
    final controller = _nativeController(tester);
    for (
      var frame = 0;
      frame < 150 && !controller.visibleImageHasFrame;
      frame++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
    expect(controller.visibleImageHasFrame, isTrue);
    final location = controller.visibleView!.coverage.locate(
      original.anchor,
    ) as NovelReaderNativeImageCoverage;
    expect(location.imageIndex, 1);
    expect(repository.progress[_chapter], same(saved));

    await _changeModeViaDisplaySettings(tester, NovelReaderFlowMode.vertical);
    for (var frame = 0; frame < 250; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
      if (body.evaluate().isNotEmpty &&
          _verticalPosition(tester).pixels > prefix.first.usedHeight) {
        break;
      }
    }
    final returned = await capture();
    expect(returned.anchor.nodeId, original.anchor.nodeId);
    expect(returned.anchor.textIdentity, original.anchor.textIdentity);
    expect(returned.imageProgress, closeTo(original.imageProgress, .003));
    expect(repository.progress[_chapter], same(saved));
    expect(repository.committed, isEmpty);
    expect(repository.completed, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final floated in [false, true]) {
    testWidgets(
      'scrolling table reflow keeps the visible source without saving (floated=$floated)',
      (tester) async {
        final rows = List.generate(
          18,
          (row) =>
              '<tr height="88"><td width="850">左列 $row</td>'
              '<td width="810">右列第 $row 行，继续阅读同一处文字。</td></tr>',
        ).join();
        final markup = '<table width="1660" cellpadding="0">$rows</table>';
        final placed = floated
            ? '<span style="float:right;width:300px;margin-left:5px">$markup</span>'
                  '表旁文字<br style="clear:both">'
            : markup;
        final repository = _ReadingRepository('<p>表格前</p>$placed<p>表格后</p>');
        final saved = NovelReadingProgress(
          novelId: _work,
          episodeId: _chapter,
          scrollOffset: 0,
          updatedAt: DateTime(2026, 10, 1),
        );
        repository.progress[_chapter] = saved;
        repository.recent = _chapter;
        await tester.pumpWidget(
          _app(
            repository,
            nativePagination: true,
            preferences: NovelReaderPreferences.defaults().copyWith(
              flowMode: NovelReaderFlowMode.vertical,
            ),
          ),
        );
        final flow = find.byType(ForumBodyFlowSliver);
        final table = find.byType(ForumBodyTableFlowViewport);
        Future<ForumBodyFlowSliver> rendered({
          ForumBodyTextPageSession? after,
        }) async {
          for (var frame = 0; frame < 250; frame++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
            await tester.pump();
            if (flow.evaluate().isEmpty || table.evaluate().isEmpty) continue;
            final widget = tester.widget<ForumBodyFlowSliver>(flow);
            if (widget.prefix.isComplete && !identical(widget.session, after)) {
              await tester.pumpAndSettle();
              return tester.widget<ForumBodyFlowSliver>(flow);
            }
          }
          throw StateError('Flowing table did not present a complete layout');
        }

        final original = await rendered();
        double? offsetFor(ForumBodyFlowSliver widget) {
          if (!floated) return widget.initialTableOffset?.offset;
          final slice = widget.prefix.singleWhere(
            (page) => page.floatedTables.isNotEmpty,
          );
          return widget.session.flowTableOffset(
            slice.index,
            slice.floatedTables.single.path,
          );
        }

        final outer = _verticalPosition(tester);
        outer.jumpTo(450);
        await tester.pumpAndSettle();
        tester
            .widget<ForumBodyTableFlowViewport>(table)
            .horizontalController
            .jumpTo(875);
        await tester.pumpAndSettle();
        expect(repository.progress[_chapter], same(saved));

        _controller(
          tester,
        ).previewPreferences(_state(tester).preferences.copyWith(fontSize: 27));
        final next = await rendered(after: original.session);
        expect(original.session.isClosed, isTrue);
        expect(offsetFor(next), greaterThan(800));
        expect(
          tester
              .widget<ForumBodyTableFlowViewport>(table)
              .horizontalController
              .offset,
          greaterThan(800),
        );
        expect(_verticalPosition(tester).pixels, closeTo(450, 88));
        expect(repository.progress[_chapter], same(saved));
        expect(repository.committed, isEmpty);

        addTearDown(tester.view.resetPhysicalSize);
        tester.view.physicalSize =
            const Size(680, 600) * tester.view.devicePixelRatio;
        final resized = await rendered(after: next.session);
        expect(resized.prefix.width, lessThan(next.prefix.width));
        expect(offsetFor(resized), greaterThan(800));
        expect(_verticalPosition(tester).pixels, closeTo(450, 88));

        _controller(
          tester,
        ).previewPreferences(_state(tester).preferences.copyWith(fontSize: 31));
        await tester.pump();
        expect(
          tester.widget<ForumBodyFlowSliver>(flow).session,
          same(resized.session),
        );
        _verticalPosition(tester).jumpTo(0);
        final afterMovement = await rendered(after: resized.session);
        expect(offsetFor(afterMovement) ?? 0, 0);
        expect(_verticalPosition(tester).pixels, 0);
        expect(repository.progress[_chapter], same(saved));
        expect(repository.committed, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(afterMovement.session.isClosed, isTrue);
      },
    );
  }

  testWidgets(
    'native scrolling reader restores against the complete table extent',
    (tester) async {
      final repository = _ReadingRepository(
        '<p>表格前</p><table width="950" cellpadding="0">'
        '<tr height="1250"><td width="475">左列</td><td width="475">右列</td></tr>'
        '<tr><td colspan="2">表格底部</td></tr></table><p>表格后</p>',
      );
      final saved = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        flowMode: NovelReaderFlowMode.pagedLtr,
        scrollOffset: 0,
        pageIndex: 2,
        pageCount: 5,
        paginationKey: 'previous-book-layout',
        progressPercent: .4,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.pagedStartV1,
        updatedAt: DateTime(2026, 10, 1),
      );
      repository.progress[_chapter] = saved;
      repository.recent = _chapter;
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.vertical,
          ),
        ),
      );
      final flow = find.byType(ForumBodyFlowSliver);
      final table = find.byType(ForumBodyTableFlowViewport);
      for (var frame = 0; frame < 250; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
        if (flow.evaluate().isNotEmpty &&
            tester
                .renderObject<RenderForumBodyFlowBoundary>(flow)
                .finalBoundaryKnown &&
            _verticalPosition(tester).pixels > 0 &&
            table.evaluate().isNotEmpty) {
          break;
        }
      }
      expect(flow, findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(NovelReaderHtmlDocumentView), findsNothing);
      expect(
        tester
            .renderObject<RenderForumBodyFlowBoundary>(flow)
            .finalBoundaryKnown,
        isTrue,
      );
      expect(table, findsOneWidget);
      final geometry = _bodyLayout(tester);
      final position = _verticalPosition(tester);
      final expected =
          geometry.bodyTop + .4 * geometry.bodyRange - geometry.topChrome;
      expect(geometry.bodyRange, greaterThan(500));
      expect(position.pixels, closeTo(expected, 1));
      final horizontal = tester
          .widget<ForumBodyTableFlowViewport>(table)
          .horizontalController;
      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      final point =
          tester.getTopLeft(
            find.byKey(const Key('novel-reader-paragraph-list')),
          ) +
          const Offset(430, 280);
      await tester.dragFrom(point, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(horizontal.offset, greaterThan(0));
      expect(position.pixels, closeTo(expected, 1));
      expect(repository.progress[_chapter], same(saved));
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);

      final owner = tester
          .widget<NovelReaderNativeFlowHost>(
            find.byType(NovelReaderNativeFlowHost),
          )
          .owner;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(owner.isClosed, isTrue);
      expect(owner.activeCacheHandles, 0);
      expect(repository.progress[_chapter], same(saved));
    },
  );

  for (final future in [false, true]) {
    testWidgets(
      'native main reader opens the exact repeated image and returns without migrating its position: future=$future',
      (tester) async {
        const image =
            '<img width="400" height="400" src="https://bbs.yamibo.com/data/attachment/forum/a.png">';
        final repository = _ReadingRepository('$image$image');
        if (future) {
          repository.progress[_chapter] = NovelReadingProgress(
            novelId: _work,
            episodeId: _chapter,
            scrollOffset: 0,
            updatedAt: DateTime(2026),
            flowMode: NovelReaderFlowMode.pagedLtr,
            pageIndex: 1,
            pageCount: 2,
            paginationKey: 'obsolete-image-layout',
            anchorNodeId: 'node-1',
            anchorTextOffset: -17,
            anchorFormatVersion: 37,
            anchorTextIdentity: 'future-image-identity',
            progressPercent: .5,
            isProgressPercentValid: true,
          );
        }
        final navigation = GlobalKey<NavigatorState>();
        final images = _PendingImageCache();
        await tester.pumpWidget(
          _app(
            repository,
            nativePagination: true,
            navigation: navigation,
            images: images,
          ),
        );
        await _pumpNativeReady(tester);
        final original = _nativeController(tester);
        if (!future) expect(original.requestPage(1), isTrue);
        await _pumpNativeReady(tester, page: 1);
        await tester.pump(const Duration(milliseconds: 300));
        final before = repository.progress[_chapter]!;
        final owner = tester
            .widget<NovelReaderNativePagedSurface>(
              find.byType(NovelReaderNativePagedSurface),
            )
            .owner;
        final rect = tester.getRect(find.byType(ForumHtmlImageView).first);
        // Exercise a page-turn tap zone, not only the center menu zone.
        final point = Offset(rect.right - 2, rect.center.dy);
        await tester.tapAt(point);
        await tester.tapAt(point);
        for (
          var frame = 0;
          frame < 60 && find.byType(ThreadImageReaderPage).evaluate().isEmpty;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byType(ThreadImageReaderPage, skipOffstage: false),
          findsOneWidget,
        );
        final request = tester
            .widget<ThreadImageReaderPage>(find.byType(ThreadImageReaderPage))
            .request;
        expect(request.initialIndex, 1);
        expect(request.initialEntry!.indexInPost, 1);
        expect(request.group.entries, hasLength(2));
        expect(request.group.entries.map((e) => e.url).toSet(), hasLength(1));
        expect(request.continuousImages.map((e) => e.id).toSet(), hasLength(2));
        expect(request.tid, '100');
        expect(request.pid, _chapter);
        expect(
          request.continuousImages.every((e) => e.cacheKey.isNotEmpty),
          isTrue,
        );
        expect(original.isSuspended, isTrue);
        expect(repository.completed, isEmpty);
        await navigation.currentState!.maybePop();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await _pumpNativeReady(tester, page: 1, advanceTime: true);
        expect(find.byType(ThreadImageReaderPage), findsNothing);
        expect(_nativeController(tester), same(original));
        expect(
          repository.progress[_chapter]!.anchorNodeId,
          before.anchorNodeId,
        );
        expect(
          repository.progress[_chapter]!.anchorTextIdentity,
          before.anchorTextIdentity,
        );
        expect(repository.progress[_chapter]!.pageIndex, 1);
        expect(
          repository.progress[_chapter]!.anchorFormatVersion,
          future ? 37 : 1,
        );
        expect(
          repository.progress[_chapter]!.anchorTextOffset,
          before.anchorTextOffset,
        );
        expect(repository.completed, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(owner.isClosed, isTrue);
        expect(owner.activeCacheHandles, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a delayed image-opening flush cannot open above another route', (
    tester,
  ) async {
    const image =
        '<img width="400" height="400" src="https://bbs.yamibo.com/data/attachment/forum/a.png">';
    final repository = _ReadingRepository('$image$image');
    final navigation = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(repository, nativePagination: true, navigation: navigation),
    );
    await _pumpNativeReady(tester);
    final gate = repository.commitGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.tap(find.byType(ForumHtmlImageView).first);
    await tester.pump();
    expect(find.byType(ThreadImageReaderPage), findsNothing);
    final covering = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.expand(),
    );
    unawaited(navigation.currentState!.push<void>(covering));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    gate.complete();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byType(ThreadImageReaderPage, skipOffstage: false),
      findsNothing,
    );
    expect(covering.isCurrent, isTrue);
    navigation.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpNativeReady(tester, page: 0, advanceTime: true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'controlled native entry renders and commits through the reader',
    (tester) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      expect(find.byType(NovelReaderHtmlPagedSurface), findsNothing);
      expect(
        find.byKey(const Key('novel-reader-delayed-loading-surface')),
        findsNothing,
      );
      final native = tester.widget<NovelReaderNativePagedSurface>(
        find.byType(NovelReaderNativePagedSurface),
      );
      final controller = _nativeController(tester);
      expect(native.resolvedFont.id, native.preferences.fontFamily);
      expect(controller.snapshot!.length, greaterThan(2));
      expect(controller.visiblePageIndex, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter]!.anchorFormatVersion, 1);
      expect(
        repository.progress[_chapter]!.paginationKey,
        controller.paginationKey,
      );
      expect(repository.completed, isEmpty);
      final owner = native.owner;
      await tester.pumpWidget(const SizedBox());
      expect(owner.isClosed, isTrue);
      expect(owner.activeCacheHandles, 0);
      expect(owner.estimatedRetainedBytes, 0);
    },
  );

  testWidgets('native main reader accepts a fitted edit notice before the body', (
    tester,
  ) async {
    final repository = _ReadingRepository(
      '<i class="pstatus"> Edited&nbsp;by <span>Reader</span><br> at 2026 </i><br><br>$_nativeLongBody',
    );
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final controller = _nativeController(tester);
    expect(controller.visiblePageIndex, 0);
    expect(controller.error, isNull);
    expect(controller.snapshot!.length, greaterThan(2));
    expect(find.byType(NovelReaderHtmlPagedSurface), findsNothing);
    expect(
      find.byKey(const Key('novel-reader-pagination-fallback')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.progress[_chapter]!.anchorFormatVersion, 1);
    expect(repository.completed, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native completion waits for the actual menu slide out', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>完整而短的一章。</p>');
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final overlay = tester
        .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
        .controller!;
    final controller = _nativeController(tester);
    overlay.showMenu();
    expect(controller.isSuspended, isTrue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.completed, isEmpty);

    overlay.hideMenu();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.isSuspended, isTrue);
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 120));
    await _pumpNativeReady(tester);
    expect(_nativeController(tester), same(controller));
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 249));
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native lifecycle pauses work before an inactive frame', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>暂停前的短章。</p>');
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final controller = _nativeController(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(controller.isSuspended, isTrue);
    await tester.pump(const Duration(hours: 1));
    expect(repository.completed, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpNativeReady(tester);
    expect(_nativeController(tester), same(controller));
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox());
  });

  for (final lifecycle in [false, true]) {
    testWidgets('frameless native hide/resume keeps the qualified flush lease '
        '(lifecycle: $lifecycle)', (tester) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      final gate = repository.commitGate = Completer<void>();
      if (lifecycle) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        final overlay = tester
            .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
            .controller!;
        overlay.showMenu();
        overlay.hideMenu();
      }
      await _pumpNativeReady(tester);
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter]!.anchorFormatVersion, 1);
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final rtl in [false, true]) {
    testWidgets('native side tap closes the menu and turns once (rtl: $rtl)', (
      tester,
    ) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: rtl
                ? NovelReaderFlowMode.pagedRtl
                : NovelReaderFlowMode.pagedLtr,
          ),
        ),
      );
      await _pumpNativeReady(tester);
      final overlayFinder = find.byType(ReaderOverlayScaffold);
      tester
          .widget<ReaderOverlayScaffold>(overlayFinder)
          .controller!
          .showMenu();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final overlay = tester.widget<ReaderOverlayScaffold>(overlayFinder);
      (rtl ? overlay.onLeftTap : overlay.onRightTap)!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_nativeController(tester).visiblePageIndex, 0);
      await tester.pump(const Duration(milliseconds: 120));
      await _pumpNativeReady(tester, page: 1, advanceTime: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter]!.pageIndex, 1);
      expect(_nativeController(tester).visiblePageIndex, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'chapter search jumps to the actual hit and highlights after reflow',
    (tester) async {
      final repository = _ReadingRepository(
        '$_nativeLongBody<p>Unique high<b>light</b> needle</p>',
      );
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      final first = _nativeController(tester);
      final last = first.snapshot!.length - 1;
      expect(last, greaterThan(0));
      final reader = find.byType(NovelReaderPage);
      final l10n = AppLocalizations.of(tester.element(reader));
      final overlay = tester
          .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
          .controller!;
      overlay.showMenu();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('shared-reader-top-action-search-text')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('novel-reader-text-search-field')),
        'highlight',
      );
      await tester.pump();
      await tester.tap(find.byTooltip(l10n.commonSearch));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.textContaining('highlight'),
        ),
      );
      await _pumpNativeReady(tester, page: last, advanceTime: true);

      List<Rect> paintedRects() {
        final highlight = tester.widget<ForumBodyTextHighlight>(
          find.byType(ForumBodyTextHighlight),
        );
        expect(highlight.ranges, isNotEmpty);
        return [
          for (final page in tester.widgetList<ForumBodyTextPageSurface>(
            find.byType(ForumBodyTextPageSurface),
          ))
            ...page.locateSourceRanges(highlight.ranges),
        ];
      }

      final before = paintedRects();
      expect(before, isNotEmpty);
      final container = ProviderScope.containerOf(
        tester.element(reader),
        listen: false,
      );
      container
          .read(novelReaderControllerProvider(_args).notifier)
          .previewPreferences(
            _state(tester).preferences.copyWith(fontSize: 27),
          );
      await tester.pump();
      await _pumpNativeReady(tester, advanceTime: true);
      expect(_nativeController(tester), isNot(same(first)));
      expect(paintedRects(), isNotEmpty);
      expect(paintedRects(), isNot(before));
      final page = _nativeController(tester).visiblePageIndex;
      overlay.showMenu();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('shared-reader-top-action-search-text')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.historySearchClear));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ForumBodyTextHighlight>(find.byType(ForumBodyTextHighlight))
            .ranges,
        isEmpty,
      );
      expect(_nativeController(tester).visiblePageIndex, page);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in [
    NovelReaderFlowMode.vertical,
    NovelReaderFlowMode.pagedLtr,
  ]) {
    testWidgets('position bookmark saves and reveals a mounted glyph ($mode)', (
      tester,
    ) async {
      final vertical = mode == NovelReaderFlowMode.vertical;
      final repository = _ReadingRepository(_nativeLongBody);
      final stale = NovelReaderBookmark(
        bookmarkId: 'reader-bookmark:stale',
        novelId: _work,
        episodeId: _chapter,
        anchor: const NovelReaderTextAnchor(
          episodeId: _chapter,
          nodeId: 'node-0',
          formatVersion: 1,
          textIdentity: 'changed',
        ),
        title: '旧书签',
        snippet: '',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      );
      if (vertical) repository.bookmarks.add(stale);
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: mode,
          ),
        ),
      );
      final flow = find.byType(ForumBodyFlowSliver);
      Future<void> waitForFlow(bool Function() ready) async {
        for (var frame = 0; frame < 225; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump(const Duration(milliseconds: 8));
          if (flow.evaluate().isNotEmpty && ready()) return;
        }
        fail('The scrolling reader did not confirm the requested position');
      }

      final dialog = find.byType(NovelReaderPositionBookmarksDialog);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderPage)),
      );
      ReaderOverlayController overlay() => tester
          .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
          .controller!;
      Future<void> openBookmarks() async {
        overlay().showMenu();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('shared-reader-top-action-position-bookmarks')),
        );
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget);
      }

      const destinationPage = 3;
      if (vertical) {
        await waitForFlow(
          () => tester.widget<ForumBodyFlowSliver>(flow).prefix.isComplete,
        );
        await tester.pumpAndSettle();
        _verticalPosition(tester).jumpTo(1300);
        await tester.pumpAndSettle();
        expect(_verticalPosition(tester).pixels, 1300);
      } else {
        await _pumpNativeReady(tester);
        expect(_nativeController(tester).requestPage(destinationPage), isTrue);
        await _pumpNativeReady(
          tester,
          page: destinationPage,
          advanceTime: true,
        );
      }
      await openBookmarks();
      await tester.tap(find.text(l10n.novelSavePositionBookmark));
      await tester.pumpAndSettle();
      final saved = repository.bookmarks.last;
      expect(saved.anchor.hasCanonicalTextOffset, isTrue);
      expect(saved.anchor.nodeId, isNot('node-0'));
      expect(saved.snippet, contains('小说正文'));
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();

      if (vertical) {
        overlay().showMenu();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('shared-reader-bottom-action-catalog')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(NovelReaderChapterListSheet),
            matching: find.text('下一章'),
          ),
        );
        await waitForFlow(
          () => _state(tester).currentEpisode.episodeId == _next,
        );
        await tester.pumpAndSettle();
        repository.progress[_chapter] = NovelReadingProgress(
          novelId: _work,
          episodeId: _chapter,
          scrollOffset: 140,
          updatedAt: DateTime(2026, 10, 1),
        );
      } else {
        overlay().hideMenu();
        await _pumpNativeReady(tester, advanceTime: true);
        expect(_nativeController(tester).requestPage(0), isTrue);
        await _pumpNativeReady(tester, page: 0, advanceTime: true);
      }

      await openBookmarks();
      await tester.tap(find.byKey(ValueKey(saved.bookmarkId)));
      if (vertical) {
        await waitForFlow(
          () =>
              _state(tester).currentEpisode.episodeId == _chapter &&
              _state(tester).progressSnapshot.scrollOffset > 1000,
        );
      } else {
        await _pumpNativeReady(
          tester,
          page: destinationPage,
          advanceTime: true,
        );
        expect(
          _nativeController(tester).visibleView!.coverage.locate(saved.anchor),
          isNotNull,
        );
      }
      final highlight = tester.widget<ForumBodyTextHighlight>(
        find.byType(ForumBodyTextHighlight),
      );
      expect(highlight.ranges, isNotEmpty);
      expect(
        tester
            .widgetList<ForumBodyTextPageSurface>(
              find.byType(ForumBodyTextPageSurface),
            )
            .any(
              (surface) =>
                  surface.locateSourceRanges(highlight.ranges).isNotEmpty,
            ),
        isTrue,
      );

      await openBookmarks();
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey(saved.bookmarkId)),
          matching: find.byTooltip(l10n.commonRemove),
        ),
      );
      await tester.pumpAndSettle();
      if (vertical) {
        final before = _verticalPosition(tester).pixels;
        await tester.tap(find.byKey(ValueKey(stale.bookmarkId)));
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.novelBookmarkPositionUnavailable),
          findsOneWidget,
        );
        expect(_verticalPosition(tester).pixels, before);
        expect(repository.bookmarks, [same(stale)]);
      } else {
        expect(repository.bookmarks, isEmpty);
        expect(find.text(l10n.novelNoPositionBookmarks), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final destination in ['paragraph', 'table', 'floated table']) {
    testWidgets('vertical search proves an offscreen hit in $destination', (
      tester,
    ) async {
      const table =
          '<table width="1600"><tr height="140"><td width="900">First cell</td>'
          '<td width="700">Unique highlight needle</td></tr></table>';
      final inTable = destination != 'paragraph';
      if (inTable) {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      final tail = switch (destination) {
        'floated table' =>
          '<span style="float:right;width:300px">$table</span>'
              '旁边正文<br style="clear:both">',
        'table' => table,
        _ => '<p>Unique high<b>light</b> needle</p>',
      };
      final filler = inTable
          ? _nativeLongBody
          : List.generate(700, (i) => '<p>第$i段小说正文</p>').join();
      final idle = Completer<void>();
      addTearDown(idle.complete);
      final repository = _ReadingRepository('$filler$tail');
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          nativeIdleScheduler: inTable ? null : () => idle.future,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.vertical,
          ),
        ),
      );
      final flow = find.byType(ForumBodyFlowSliver);
      final host = find.byType(NovelReaderNativeFlowHost);
      Future<void> waitUntil(bool Function() predicate) async {
        for (var frame = 0; frame < 225; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump(const Duration(milliseconds: 8));
          if (predicate()) return;
        }
        fail('The vertical reader did not reach the requested state');
      }

      await waitUntil(
        () =>
            flow.evaluate().isNotEmpty &&
            find.byType(ForumBodyTextPageSurface).evaluate().isNotEmpty,
      );
      final first = tester.widget<ForumBodyFlowSliver>(flow);
      final scroll = _verticalPosition(tester);
      expect(scroll.pixels, 0);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderPage)),
      );
      final overlay = tester
          .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
          .controller!;

      Future<void> chooseHit() async {
        overlay.showMenu();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 260));
        await tester.tap(
          find.byKey(const Key('shared-reader-top-action-search-text')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.enterText(
          find.byKey(const Key('novel-reader-text-search-field')),
          'highlight',
        );
        await tester.pump();
        await tester.tap(find.byTooltip(l10n.commonSearch));
        await tester.pump();
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining('highlight'),
          ),
        );
      }

      await chooseHit();
      if (!inTable) {
        // Start a real drag while the request is probing a partial prefix.
        await waitUntil(() {
          final pending = tester.widget<NovelReaderNativeFlowHost>(host);
          return pending.activity?.value == true &&
              pending.navigationRequest != null;
        });
        expect(
          tester.widget<ForumBodyFlowSliver>(flow).prefix.isComplete,
          isFalse,
        );
        await tester.drag(
          find.byKey(const Key('novel-reader-paragraph-list')),
          const Offset(0, -120),
        );
        await waitUntil(
          () =>
              !scroll.isScrollingNotifier.value &&
              tester
                      .widget<NovelReaderNativeFlowHost>(host)
                      .navigationRequest ==
                  null,
        );
        expect(scroll.pixels, greaterThan(0));
        expect(scroll.pixels, lessThan(1000));
        expect(
          tester.widget<NovelReaderNativeFlowHost>(host).textHighlight,
          isNull,
        );
        await chooseHit();
      }
      await waitUntil(
        () =>
            tester.widget<NovelReaderNativeFlowHost>(host).navigationRequest !=
            null,
      );
      await waitUntil(
        () =>
            scroll.pixels > (inTable ? 0 : 1000) &&
            tester.widget<NovelReaderNativeFlowHost>(host).navigationRequest ==
                null,
      );
      final mark = tester.widget<ForumBodyTextHighlight>(
        find.byType(ForumBodyTextHighlight),
      );
      expect(mark.ranges, isNotEmpty);
      expect(
        tester.widget<ForumBodyFlowSliver>(flow).session,
        same(first.session),
      );
      expect(
        tester
            .widgetList<ForumBodyTextPageSurface>(
              find.byType(ForumBodyTextPageSurface),
            )
            .any((page) => page.locateSourceRanges(mark.ranges).isNotEmpty),
        isTrue,
      );
      if (inTable) {
        final table = tester.widget<ForumBodyTableFlowViewport>(
          find.byType(ForumBodyTableFlowViewport),
        );
        expect(table.horizontalController.offset, greaterThan(500));
      }
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(
        repository.progress[_chapter]?.scrollOffset,
        closeTo(scroll.pixels, 1),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('native slider request closes the menu before actual arrival', (
    tester,
  ) async {
    final repository = _ReadingRepository(_nativeLongBody);
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final overlayFinder = find.byType(ReaderOverlayScaffold);
    tester.widget<ReaderOverlayScaffold>(overlayFinder).controller!.showMenu();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    tester
        .widget<ReaderOverlayScaffold>(overlayFinder)
        .bottomBar
        .progress!
        .onChangeEnd(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_nativeController(tester).visiblePageIndex, 0);
    await tester.pump(const Duration(milliseconds: 120));
    await _pumpNativeReady(tester, page: 2);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.progress[_chapter]!.pageIndex, 2);
    expect(
      tester
          .widget<ReaderOverlayScaffold>(overlayFinder)
          .bottomBar
          .progress!
          .interactionLocked,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final seek in [false, true]) {
    testWidgets('new pointer retires a turn waiting for menu dismissal '
        '(seek: $seek)', (tester) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      final overlayFinder = find.byType(ReaderOverlayScaffold);
      tester
          .widget<ReaderOverlayScaffold>(overlayFinder)
          .controller!
          .showMenu();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final overlay = tester.widget<ReaderOverlayScaffold>(overlayFinder);
      if (seek) {
        overlay.bottomBar.progress!.onChangeEnd(2);
      } else {
        overlay.onRightTap!();
      }
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(NovelReaderNativePagedSurface)),
      );
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 240));
      await _pumpNativeReady(tester, page: 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_nativeController(tester).visiblePageIndex, 0);
      expect(
        tester
            .widget<ReaderOverlayScaffold>(overlayFinder)
            .bottomBar
            .progress!
            .interactionLocked,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'native menu flush failure retires completion and reports the error',
    (tester) async {
      final repository = _ReadingRepository('<p>保存失败后仍可阅读的短章。</p>');
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      repository.failNextCommit = true;
      tester
          .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
          .controller!
          .showMenu();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_nativeController(tester).isSuspended, isTrue);
      expect(repository.completed, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('native reflow retains the reading owner and mounted shell', (
    tester,
  ) async {
    final repository = _ReadingRepository(_nativeLongBody);
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final surfaceFinder = find.byType(NovelReaderNativePagedSurface);
    final shellState = tester.state(surfaceFinder);
    final owner = tester
        .widget<NovelReaderNativePagedSurface>(surfaceFinder)
        .owner;
    final oldController = _nativeController(tester);
    final overlay = tester
        .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
        .controller!;
    overlay.showMenu();
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelReaderPage)),
      listen: false,
    );
    final reader = container.read(
      novelReaderControllerProvider(_args).notifier,
    );
    reader.previewPreferences(
      container
          .read(novelReaderControllerProvider(_args))
          .requireValue
          .preferences
          .copyWith(fontSize: 28),
    );
    await tester.pump();
    expect(tester.state(surfaceFinder), same(shellState));
    expect(
      tester.widget<NovelReaderNativePagedSurface>(surfaceFinder).owner,
      same(owner),
    );
    expect(oldController.isSuspended, isTrue);
    expect(repository.completed, isEmpty);
    overlay.hideMenu();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await _pumpNativeReady(tester);
    expect(_nativeController(tester), isNot(same(oldController)));
    expect(oldController.isClosed, isTrue);
    expect(tester.state(surfaceFinder), same(shellState));
    expect(
      tester
          .widget<NovelReaderNativePagedSurface>(surfaceFinder)
          .preferences
          .fontSize,
      28,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'flushing after a mode change preserves the last real page turn',
    (tester) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester, page: 0, advanceTime: true);
      await tester.tapAt(const Offset(744, 300));
      await _pumpNativeReady(tester, page: 1, advanceTime: true);
      await tester.pump(const Duration(milliseconds: 350));
      expect(repository.progress[_chapter]?.pageIndex, 1);

      await _changeModeViaDisplaySettings(tester, NovelReaderFlowMode.vertical);
      final flow = find.byType(ForumBodyFlowSliver);
      for (var frame = 0; frame < 250; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        if (flow.evaluate().isNotEmpty &&
            tester.widget<ForumBodyFlowSliver>(flow).prefix.isComplete &&
            _verticalPosition(tester).pixels > 0) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(_verticalPosition(tester).pixels, greaterThan(0));
      final saved = repository.progress[_chapter]!;
      final writes = repository.committed.length;
      expect(saved.flowMode, NovelReaderFlowMode.pagedLtr);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(repository.progress[_chapter], same(saved));
      expect(repository.committed, hasLength(writes));
      expect(repository.completed, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        repository.progress[_chapter]?.flowMode,
        NovelReaderFlowMode.vertical,
      );
      expect(repository.committed.length, greaterThan(writes));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('explicit scroll choice carries the paused visible page source', (
    tester,
  ) async {
    final repository = _ReadingRepository(
      '$_nativeLongBody<div style="position:absolute">unsupported</div>',
    );
    await tester.pumpWidget(_app(repository, nativePagination: true));
    final fallback = find.byKey(const Key('novel-reader-pagination-fallback'));
    for (var frame = 0; frame < 250 && fallback.evaluate().isEmpty; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
    expect(fallback, findsOneWidget);
    final controller = _nativeController(tester);
    expect(controller.visiblePageIndex, 0);
    expect(controller.requestPage(2), isTrue);
    for (
      var frame = 0;
      frame < 250 && controller.visiblePageIndex != 2;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.visiblePageIndex, 2);
    expect(controller.error, isNotNull);
    final expected = controller.visibleView!.coverage.locations.first.anchor;
    final saved = repository.progress[_chapter];
    final writes = repository.committed.length;

    await tester.tap(fallback);
    await tester.pump();
    final flow = tester.widget<NovelReaderNativeFlowHost>(
      find.byType(NovelReaderNativeFlowHost),
    );
    expect(flow.initialSource?.anchor.nodeId, expected.nodeId);
    expect(flow.initialSource?.anchor.textOffset, expected.textOffset);
    expect(controller.isClosed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(repository.progress[_chapter], same(saved));
    expect(repository.committed, hasLength(writes));
    expect(flow.owner.activeCacheHandles, 0);
  });

  testWidgets(
    'native failure preserves the mode until explicit scroll choice',
    (tester) async {
      final repository = _ReadingRepository('<p>不会被自动旧渲染器接管的正文。</p>');
      final preparation = _NativePreparationProbe()..fail = true;
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          nativePreparation: preparation,
        ),
      );
      for (
        var frame = 0;
        frame < 100 &&
            find
                .byKey(const Key('novel-reader-pagination-fallback'))
                .evaluate()
                .isEmpty;
        frame++
      ) {
        await tester.pump();
      }
      expect(
        find.byKey(const Key('novel-reader-pagination-fallback')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(preparation.calls, 1);
      expect(find.byType(NovelReaderHtmlPagedSurface), findsNothing);
      expect(repository.committed, isEmpty);
      expect(
        tester
            .widget<NovelReaderNativePagedSurface>(
              find.byType(NovelReaderNativePagedSurface),
            )
            .preferences
            .flowMode,
        NovelReaderFlowMode.pagedLtr,
      );
      await tester.tap(
        find.byKey(const Key('novel-reader-pagination-fallback')),
      );
      for (var frame = 0; frame < 100 && preparation.calls < 2; frame++) {
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(NovelReaderNativePagedSurface), findsNothing);
      expect(find.byType(NovelReaderNativeFlowHost), findsOneWidget);
      expect(find.byType(NovelReaderHtmlDocumentView), findsNothing);
      expect(preparation.calls, 2);
      expect(
        find.byKey(const Key('novel-reader-paragraph-list')),
        findsOneWidget,
      );
      expect(repository.committed, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final hideWithRoute in [false, true]) {
    testWidgets('late native preparation cannot report under a hidden reader '
        '(route: $hideWithRoute)', (tester) async {
      final repository = _ReadingRepository('<p>等待准备时遮挡的完整短章。</p>');
      final preparation = _NativePreparationProbe()..gate = Completer<void>();
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          nativePreparation: preparation,
          navigation: navigation,
        ),
      );
      for (var frame = 0; frame < 100 && preparation.calls == 0; frame++) {
        await tester.pump();
      }
      expect(preparation.calls, 1);
      if (hideWithRoute) {
        unawaited(
          navigation.currentState!.push<void>(
            MaterialPageRoute(builder: (_) => const Scaffold(body: SizedBox())),
          ),
        );
        await tester.pump();
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      preparation.gate!.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);
      if (hideWithRoute) {
        navigation.currentState!.pop();
        await tester.pumpAndSettle();
      } else {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await _pumpNativeReady(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(repository.completed, [_chapter]);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'source menu actual body reading returns to the latest common position',
    (tester) async {
      final repository = _ReadingRepository(
        List.generate(100, (index) => '<p>小说与原帖公共正文第 $index 段。</p>')
            .join(),
      );
      final sourceRepository = _SourceThreadRepository(repository.html);
      final locator = _SourcePostLocator();
      await tester.pumpWidget(
        _app(repository, threadRepository: sourceRepository, locator: locator),
      );
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      final before = _verticalPosition(tester).pixels;
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('novel-reader-paragraph-list'))),
      );
      await tester.pump(const Duration(milliseconds: 330));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('shared-reader-top-action-open-thread')),
      );
      await tester.pumpAndSettle();
      final sourcePage = tester.widget<ThreadDetailPage>(
        find.byType(ThreadDetailPage),
      );
      expect(sourcePage.targetPid, '5001');
      expect(sourcePage.landing, ThreadPostLanding.top);
      expect(sourcePage.bodyReadingObserver, isNotNull);
      expect(sourcePage.nativeBody, isTrue);
      expect(locator.calls, 1);
      final priorSource = repository.progress[_chapter]!;
      expect(priorSource.progressPercent, greaterThan(0));
      final sourceScroll = find.descendant(
        of: find.byType(ThreadDetailPage),
        matching: find.byType(CustomScrollView),
      );
      await tester.drag(sourceScroll, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final sourceProgress = repository.progress[_chapter]!;
      expect(
        sourceProgress.progressPercent,
        greaterThan(priorSource.progressPercent),
      );
      expect(
        sourceProgress.percentBasis,
        NovelProgressPercentBasis.bodyGeometryV1,
      );
      expect(sourceProgress.anchorNodeId, isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final geometry = _bodyLayout(tester);
      final restored = _verticalPosition(tester).pixels;
      final restoredFraction =
          (restored + geometry.topChrome - geometry.bodyTop) /
          geometry.bodyRange;
      // The comparison list estimates offscreen heights until they are laid out.
      expect(restoredFraction, closeTo(sourceProgress.progressPercent, .002));
      expect(_verticalPosition(tester).pixels, greaterThan(before));
      expect(repository.progress[_chapter], same(sourceProgress));
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unchanged paged return retires old navigation without remounting HTML',
    (tester) async {
      final repository = _ReadingRepository(
        List.generate(
          16,
          (index) => '<p>第$index段：${List.filled(40, '小说正文').join()}。</p>',
        ).join(),
      );
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          repository,
          navigation: navigation,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          ),
          threadRepository: _SourceThreadRepository(repository.html),
          locator: _SourcePostLocator(),
        ),
      );
      await _pumpPagedReady(tester);
      final surfaceFinder = find.byType(NovelReaderHtmlPagedSurface);
      tester
          .widget<NovelReaderHtmlPagedSurface>(surfaceFinder)
          .navigationController!
          .turnNext();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final mountedSurface = tester.state(surfaceFinder);
      final before = _state(tester);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 330));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('shared-reader-top-action-open-thread')),
      );
      await tester.pumpAndSettle();
      final sourceOtherChapter = NovelReadingProgress(
        novelId: _work,
        episodeId: _next,
        scrollOffset: 0,
        progressPercent: .2,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 8),
      );
      await repository.commitProgress(progress: sourceOtherChapter);
      final commitCount = repository.committed.length;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final surface = tester.widget<NovelReaderHtmlPagedSurface>(surfaceFinder);
      surface.onImagesReadyChanged!(true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.state(surfaceFinder), same(mountedSurface));
      expect(
        _state(tester).readingSurfaceRevision,
        before.readingSurfaceRevision,
      );
      expect(repository.recent, _next);
      expect(repository.committed, hasLength(commitCount));
      surface.navigationController!.turnNext();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.recent, _chapter);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'source body percentage restores the actual paged surface read-only',
    (tester) async {
      final repository = _ReadingRepository(
        List.generate(
          16,
          (index) => '<p>第$index段：${List.filled(40, '小说正文').join()}。</p>',
        ).join(),
      );
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          repository,
          navigation: navigation,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          ),
        ),
      );
      await _pumpPagedReady(tester);
      final controller = _controller(tester);
      final handoff = controller.beginSourceReadingHandoff()!;
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('原帖'))),
        ),
      );
      await tester.pumpAndSettle();
      final source = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        progressPercent: .6,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 8),
      );
      await repository.commitProgress(progress: source);
      final commitCount = repository.committed.length;
      await controller.acceptSourceReadingReturn(handoff);
      navigation.currentState!.pop();
      await _pumpPagedReady(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      final pageView = tester.widget<PageView>(
        find.byKey(const Key('novel-reader-paged-page-view')),
      );
      final count = pageView.childrenDelegate.estimatedChildCount!;
      expect(count, greaterThan(1));
      expect(pageView.controller!.page, (.6 * count).floor().toDouble());
      expect(repository.progress[_chapter], same(source));
      expect(repository.committed, hasLength(commitCount));
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'source handoff returns to the latest body position without rewriting it',
    (tester) async {
      final repository = _ReadingRepository(
        '<div style="height: 2000px">原帖往返正文。</div>',
      );
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(repository, navigation: navigation));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      final controller = _controller(tester);
      await controller.saveCurrentProgressNow(_state(tester).progressSnapshot);
      final revision = _state(tester).readingSurfaceRevision;
      final handoff = controller.beginSourceReadingHandoff()!;
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('原帖'))),
        ),
      );
      await tester.pumpAndSettle();
      final source = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        progressPercent: .65,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 8),
      );
      await repository.commitProgress(progress: source);
      final commitCount = repository.committed.length;
      await controller.acceptSourceReadingReturn(handoff);
      navigation.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      final geometry = _bodyLayout(tester);
      final expected =
          geometry.bodyTop + .65 * geometry.bodyRange - geometry.topChrome;
      expect(_verticalPosition(tester).pixels, closeTo(expected, 1));
      expect(_state(tester).readingSurfaceRevision, revision + 1);
      expect(_state(tester).progressSnapshot.progressPercent, .65);
      expect(repository.committed, hasLength(commitCount));
      expect(repository.progress[_chapter], same(source));
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter], same(source));
    },
  );

  testWidgets(
    'source reset returns to the head without establishing a new position',
    (tester) async {
      final repository = _ReadingRepository(
        '<div style="height: 1600px">原帖重置正文。</div>',
      );
      repository.progress[_chapter] = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        progressPercent: .5,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 1),
      );
      repository.recent = _chapter;
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(repository, navigation: navigation));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.pumpAndSettle();
      expect(_verticalPosition(tester).pixels, greaterThan(0));
      final controller = _controller(tester);
      final handoff = controller.beginSourceReadingHandoff()!;
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('原帖'))),
        ),
      );
      await tester.pumpAndSettle();
      repository.progress.clear();
      repository.recent = null;
      await controller.acceptSourceReadingReturn(handoff);
      navigation.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_verticalPosition(tester).pixels, 0);
      expect(repository.progress, isEmpty);
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('fresh short body completes only after stable real display', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>完整的短章正文。</p>');
    await tester.pumpWidget(_app(repository));
    await _pumpBodyWithoutAdvancingTime(tester);
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 249));
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(repository.completed, [_chapter]);
    expect(repository.progress[_chapter]!.progressPercent, 0);
    expect(repository.progress[_chapter]!.isProgressPercentValid, isTrue);
    expect(
      repository.progress[_chapter]!.percentBasis,
      NovelProgressPercentBasis.bodyGeometryV1,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'passive chapter resume preserves another chapter recent reference',
    (tester) async {
      final repository = _ReadingRepository('<p>短章历史正文。</p>');
      final saved = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        progressPercent: 0,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 1),
      );
      repository.progress[_chapter] = saved;
      repository.progress[_next] = NovelReadingProgress(
        novelId: _work,
        episodeId: _next,
        scrollOffset: 100,
        progressPercent: 0.25,
        isProgressPercentValid: true,
        updatedAt: DateTime(2026, 10, 2),
      );
      repository.recent = _next;
      await tester.pumpWidget(_app(repository));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.completed, isEmpty);
      expect(repository.committed, isEmpty);
      expect(repository.recent, _next);
      expect(repository.progress[_chapter], same(saved));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.recent, _next);
      expect(repository.progress[_chapter], same(saved));
    },
  );

  testWidgets('actual body percentage excludes chrome padding and transition', (
    tester,
  ) async {
    final repository = _ReadingRepository(
      '<div style="height: 1600px">长章正文。</div>',
    );
    await tester.pumpWidget(_app(repository));
    await _pumpBodyWithoutAdvancingTime(tester);
    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    final bodyFinder = find.byType(NovelReadingBodySliver);
    final body = tester.renderObject<RenderSliver>(bodyFinder);
    final padding =
        tester
                .widget<SliverPadding>(
                  find.byKey(const Key('novel-reader-content-column')),
                )
                .padding
            as EdgeInsets;
    final position = _verticalPosition(tester);
    final topChrome = padding.top - NovelReaderSpacing.verticalPagePadding;
    final bottomChrome =
        padding.bottom - NovelReaderSpacing.verticalPagePadding;
    final range =
        body.geometry!.scrollExtent -
        (position.viewportDimension - topChrome - bottomChrome);
    final expected =
        ((position.pixels +
                    topChrome -
                    body.constraints.precedingScrollExtent) /
                range)
            .clamp(0.0, 1.0);
    final snapshot = _state(tester).progressSnapshot;
    expect(snapshot.progressPercent, closeTo(expected, 0.005));
    expect(snapshot.percentBasis, NovelProgressPercentBasis.bodyGeometryV1);
    expect(position.maxScrollExtent, greaterThan(range));
    expect(repository.completed, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending image first frame cannot complete a short chapter', (
    tester,
  ) async {
    final repository = _ReadingRepository(
      '<p>图文短章。</p><img src="https://images.test/pending.png" width="100" height="100">',
    );
    final images = _PendingImageCache();
    await tester.pumpWidget(_app(repository, images: images));
    await _pumpBodyWithoutAdvancingTime(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(images.requests, isNotEmpty);
    expect(repository.completed, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'native scrolling waits for an image first frame at chapter end',
    (tester) async {
      final repository = _ReadingRepository(
        '<p>图文短章。</p><img src="https://bbs.yamibo.com/data/attachment/forum/pending.png"'
        ' width="100" height="100">',
      );
      final images = _PendingImageCache();
      await tester.pumpWidget(
        _app(
          repository,
          images: images,
          nativePagination: true,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.vertical,
          ),
        ),
      );
      for (var frame = 0; frame < 250 && images.requests.isEmpty; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
      final flow = find.byType(ForumBodyFlowSliver);
      expect(flow, findsOneWidget);
      expect(
        tester
            .renderObject<RenderForumBodyFlowBoundary>(flow)
            .finalBoundaryKnown,
        isTrue,
      );
      expect(images.requests, isNotEmpty);
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'body percentage resumes at the same offset through safe area without rewriting history',
    (tester) async {
      const safeArea = EdgeInsets.only(top: 24, bottom: 18);
      final repository = _ReadingRepository(
        '<div style="height: 1600px">具有安全区的往返阅读正文。</div>',
      );
      await tester.pumpWidget(_app(repository, safeArea: safeArea));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final sourcePosition = _verticalPosition(tester);
      final originalOffset = sourcePosition.pixels;
      final geometry = _bodyLayout(tester);
      expect(geometry.topChrome, greaterThanOrEqualTo(safeArea.top));
      expect(geometry.bottomChrome, greaterThanOrEqualTo(safeArea.bottom));
      final saved = repository.progress[_chapter]!;
      expect(saved.progressPercent, greaterThan(0));
      expect(saved.progressPercent, lessThan(1));
      expect(saved.isProgressPercentValid, isTrue);
      expect(saved.percentBasis, NovelProgressPercentBasis.bodyGeometryV1);
      expect(saved.scrollOffset, closeTo(originalOffset, 0.5));
      expect(repository.completed, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter], same(saved));
      final originalCommitCount = repository.committed.length;
      await tester.pumpWidget(_app(repository, safeArea: safeArea));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_verticalPosition(tester).pixels, closeTo(originalOffset, 1));
      expect(
        _state(tester).progressSnapshot.progressPercent,
        closeTo(saved.progressPercent, 0.005),
      );
      expect(repository.progress[_chapter], same(saved));
      expect(repository.progress[_chapter]!.updatedAt, saved.updatedAt);
      expect(repository.committed, hasLength(originalCommitCount));
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter], same(saved));
    },
  );

  testWidgets(
    'paged body percentage restores vertical content without the transition range',
    (tester) async {
      final repository = _ReadingRepository(
        '<div style="height: 1600px">从横向阅读恢复的正文。</div>',
      );
      final saved = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        flowMode: NovelReaderFlowMode.pagedLtr,
        scrollOffset: 0,
        pageIndex: 2,
        pageCount: 5,
        paginationKey: 'previous-paged-layout',
        progressPercent: 0.4,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.pagedStartV1,
        updatedAt: DateTime(2026, 10, 1),
      );
      repository.progress[_chapter] = saved;
      repository.recent = _chapter;
      await tester.pumpWidget(
        _app(repository, safeArea: const EdgeInsets.only(top: 24, bottom: 18)),
      );
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final position = _verticalPosition(tester);
      final geometry = _bodyLayout(tester);
      final expected =
          geometry.bodyTop +
          saved.progressPercent * geometry.bodyRange -
          geometry.topChrome;
      expect(position.pixels, closeTo(expected, 1));
      expect(position.maxScrollExtent, greaterThan(geometry.bodyRange));
      expect(
        (position.pixels - saved.progressPercent * position.maxScrollExtent)
            .abs(),
        greaterThan(5),
      );
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);
      expect(repository.progress[_chapter], same(saved));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter], same(saved));
    },
  );

  testWidgets('covering the reader cancels pending short body completion', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>暂时被覆盖的短章。</p>');
    final navigation = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(repository, navigation: navigation));
    await _pumpBodyWithoutAdvancingTime(tester);
    unawaited(
      navigation.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('覆盖页面'))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.completed, isEmpty);
    navigation.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (hiddenByRoute, shortBody) in [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    testWidgets(
      'first ${shortBody ? 'short' : 'long'} body display while ${hiddenByRoute ? 'covered' : 'paused'} records history only after returning visible',
      (tester) async {
        final repository = _ReadingRepository(
          shortBody
              ? '<p>延迟准备完成的完整短章。</p>'
              : '<div style="height: 1600px">延迟准备完成的正文。</div>',
        );
        final preparation = _GatedHtmlPreparation();
        final navigation = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          _app(repository, navigation: navigation, preparation: preparation),
        );
        for (var frame = 0; frame < 200 && !preparation.started; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump();
        }
        expect(preparation.started, isTrue);
        expect(repository.committed, isEmpty);
        if (hiddenByRoute) {
          unawaited(
            navigation.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('覆盖页面')),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
        }

        preparation.gate.complete();
        if (hiddenByRoute) {
          await _pumpBodyWithoutAdvancingTime(tester, skipOffstage: false);
        } else {
          // Paused Flutter suppresses frame builds even though the underlying
          // preparation future can finish on the Dart event loop.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pump(const Duration(seconds: 1));
        expect(repository.progress, isEmpty);
        expect(repository.committed, isEmpty);
        expect(repository.completed, isEmpty);
        expect(repository.recent, isNull);

        if (hiddenByRoute) {
          navigation.currentState!.pop();
          await tester.pumpAndSettle();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        }
        await _pumpBodyWithoutAdvancingTime(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(
          ModalRoute.of(tester.element(find.byType(NovelReaderPage)))!
              .isCurrent,
          isTrue,
        );
        expect(
          _state(tester).progressSnapshot.percentBasis,
          NovelProgressPercentBasis.bodyGeometryV1,
        );
        expect(repository.committed, hasLength(shortBody ? 2 : 1));
        expect(repository.recent, _chapter);
        expect(
          repository.progress[_chapter]!.percentBasis,
          NovelProgressPercentBasis.bodyGeometryV1,
        );
        if (shortBody) {
          // A fresh first position and confirmed completion both survive the
          // same geometry publication; neither must retire the other's lease.
          expect(repository.commitCompletionFlags, [false, true]);
          expect(repository.completed, [_chapter]);
          expect(repository.progress[_chapter]!.progressPercent, 0);
        } else {
          expect(repository.commitCompletionFlags, [false]);
          expect(repository.completed, isEmpty);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('app background cancels pending completion until resumed', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>进入后台前的短章。</p>');
    await tester.pumpWidget(_app(repository));
    await _pumpBodyWithoutAdvancingTime(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(repository.completed, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real reading navigation confirms the actual long body tail', (
    tester,
  ) async {
    final repository = _ReadingRepository(
      '<div style="height: 1600px">长章的实际正文。</div>',
    );
    await tester.pumpWidget(_app(repository));
    await _pumpBodyWithoutAdvancingTime(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.completed, isEmpty);
    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -1450),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.completed, [_chapter]);
    expect(repository.progress[_chapter]!.progressPercent, 1);
    expect(repository.recent, _chapter);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _changeModeViaDisplaySettings(
  WidgetTester tester,
  NovelReaderFlowMode target,
) async {
  final overlay = tester
      .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
      .controller!;
  overlay.showMenu();
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('shared-reader-bottom-action-display')),
  );
  await tester.pumpAndSettle();
  final mode = find.byKey(const Key('novel-reader-flow-mode-control'));
  final control = tester.widget<ReaderSegmentControl<NovelReaderFlowMode>>(
    mode,
  );
  final choice = find.descendant(
    of: mode,
    matching: find.text(control.labelBuilder(target)),
  );
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  await tester.tap(choice);
  await tester.pumpAndSettle();
  Navigator.of(tester.element(mode)).pop();
}

Future<void> _pumpBodyWithoutAdvancingTime(
  WidgetTester tester, {
  bool skipOffstage = true,
}) async {
  for (var frame = 0; frame < 200; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
    if (find
            .byType(ForumHtmlWidgetPostRenderer, skipOffstage: skipOffstage)
            .evaluate()
            .isNotEmpty &&
        find
            .byKey(
              const Key('novel-reader-delayed-loading-surface'),
              skipOffstage: skipOffstage,
            )
            .evaluate()
            .isEmpty) {
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return;
    }
  }
  expect(
    find.byType(ForumHtmlWidgetPostRenderer, skipOffstage: skipOffstage),
    findsWidgets,
  );
}

NovelReaderViewState _state(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(NovelReaderPage)),
  listen: false,
).read(novelReaderControllerProvider(_args)).value!;

NovelReaderController _controller(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(NovelReaderPage)),
      listen: false,
    ).read(novelReaderControllerProvider(_args).notifier);

Future<void> _pumpPagedReady(WidgetTester tester) async {
  for (var frame = 0; frame < 200; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    final surface = find.byType(NovelReaderHtmlPagedSurface);
    if (surface.evaluate().isNotEmpty &&
        tester
                .widget<NovelReaderHtmlPagedSurface>(surface)
                .paginationCache!
                .length >
            0 &&
        find
            .byKey(const Key('novel-reader-paged-page-view'))
            .evaluate()
            .isNotEmpty) {
      return;
    }
  }
  fail('Final paged layout did not become ready');
}

ScrollPosition _verticalPosition(WidgetTester tester) => tester
    .widget<CustomScrollView>(
      find.byKey(const Key('novel-reader-paragraph-list')),
    )
    .controller!
    .position;

({double bodyTop, double bodyRange, double topChrome, double bottomChrome})
_bodyLayout(WidgetTester tester) {
  final body = tester.renderObject<RenderSliver>(
    find.byType(NovelReadingBodySliver),
  );
  final padding =
      tester
              .widget<SliverPadding>(
                find.byKey(const Key('novel-reader-content-column')),
              )
              .padding
          as EdgeInsets;
  final topChrome = padding.top - NovelReaderSpacing.verticalPagePadding;
  final bottomChrome = padding.bottom - NovelReaderSpacing.verticalPagePadding;
  return (
    bodyTop: body.constraints.precedingScrollExtent,
    bodyRange:
        body.geometry!.scrollExtent -
        (_verticalPosition(tester).viewportDimension -
            topChrome -
            bottomChrome),
    topChrome: topChrome,
    bottomChrome: bottomChrome,
  );
}

Widget _app(
  _ReadingRepository repository, {
  GlobalKey<NavigatorState>? navigation,
  _PendingImageCache? images,
  NovelReaderHtmlPreparationService? preparation,
  NovelReaderPreferences? preferences,
  ThreadRepository? threadRepository,
  ThreadPostLocator? locator,
  EdgeInsets safeArea = EdgeInsets.zero,
  bool nativePagination = false,
  NovelReaderNativePreparationService? nativePreparation,
  Future<void> Function()? nativeIdleScheduler,
}) => ProviderScope(
  overrides: [
    legacyComparisonBodyOverride,
    novelRepositoryProvider.overrideWithValue(repository),
    novelReaderPreferencesRepositoryProvider.overrideWithValue(
      _ReadingPreferences()
        ..preferences =
            preferences ??
            NovelReaderPreferences.defaults().copyWith(
              flowMode: nativePagination
                  ? NovelReaderFlowMode.pagedLtr
                  : NovelReaderFlowMode.vertical,
            ),
    ),
    novelChapterInteractionsDockPreferencesRepositoryProvider.overrideWithValue(
      _DisabledDock(),
    ),
    libraryStateRepositoryProvider.overrideWithValue(_UnusedLibraryState()),
    forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    imageCacheServiceProvider.overrideWithValue(images ?? _PendingImageCache()),
    if (preparation != null)
      novelReaderHtmlPreparationServiceProvider.overrideWithValue(preparation),
    if (nativePreparation != null)
      novelReaderNativePreparationServiceProvider.overrideWithValue(
        nativePreparation,
      ),
    if (threadRepository != null)
      threadRepositoryProvider.overrideWithValue(threadRepository),
    if (locator != null) threadPostLocatorProvider.overrideWithValue(locator),
  ],
  child: LocalizedTestApp(
    navigatorKey: navigation,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(padding: safeArea, viewPadding: safeArea),
      child: child!,
    ),
    home: NovelReaderPage(
      novelId: _work,
      initialEpisodeId: _chapter,
      nativePagination: nativePagination,
      comparisonSurfaceFactory: createLegacyNovelReaderSurface,
      nativeIdleScheduler: nativeIdleScheduler ?? _nativeIdle,
    ),
  ),
);

Future<void> _nativeIdle() async {}

final _nativeLongBody = List.generate(
  16,
  (index) => '<p>第$index段：${List.filled(40, '小说正文').join()}。</p>',
).join();

NovelReaderNativePagedController _nativeController(WidgetTester tester) =>
    tester
        .widget<NovelReaderNativePagedViewport>(
          find.byType(NovelReaderNativePagedViewport).last,
        )
        .controller;

Future<void> _pumpNativeReady(
  WidgetTester tester, {
  int? page,
  bool advanceTime = false,
}) async {
  for (var frame = 0; frame < 250; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(
      advanceTime ? const Duration(milliseconds: 16) : Duration.zero,
    );
    if (find.byType(NovelReaderNativePagedViewport).evaluate().isEmpty) {
      continue;
    }
    final controller = _nativeController(tester);
    if (!controller.isSuspended &&
        controller.snapshot?.isComplete == true &&
        controller.visiblePageIndex != null &&
        (page == null || controller.visiblePageIndex == page) &&
        !controller.hasPendingNavigation) {
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return;
    }
  }
  fail('The native reading page did not confirm the requested visible page');
}

class _NativePreparationProbe implements NovelReaderNativePreparationService {
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<NovelReaderNativeChapterPreparation> prepare({
    required String episodeId,
    required String sourceId,
    required String rawHtml,
    required NovelReaderDocument semanticDocument,
    required NovelReaderPaginationCancellationToken cancellation,
    TextConverter converter = const IdentityTextConverter(),
  }) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('test native preparation failure');
    return const DefaultNovelReaderNativePreparationService().prepare(
      episodeId: episodeId,
      sourceId: sourceId,
      rawHtml: rawHtml,
      semanticDocument: semanticDocument,
      cancellation: cancellation,
      converter: converter,
    );
  }
}

class _GatedHtmlPreparation implements NovelReaderHtmlPreparationService {
  final gate = Completer<void>();
  bool started = false;
  static const _delegate = DefaultNovelReaderHtmlPreparationService();

  @override
  int get legacyMarkupNormalizerRevision =>
      _delegate.legacyMarkupNormalizerRevision;

  @override
  Future<NovelReaderPreparedChapter> prepare({
    required String rawHtml,
    required NovelEpisodeItem episode,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
    NovelReaderDocument? semanticDocument,
  }) async {
    started = true;
    await gate.future;
    return _delegate.prepare(
      rawHtml: rawHtml,
      episode: episode,
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
      semanticDocument: semanticDocument,
    );
  }
}

class _ReadingRepository
    implements NovelRepository, NovelReadingStateRepository {
  _ReadingRepository(this.html);
  final String html;
  final progress = <String, NovelReadingProgress>{};
  final bookmarks = <NovelReaderBookmark>[];
  final states = <String, LibraryEpisodeState>{};
  final committed = <NovelReadingProgress>[];
  final commitCompletionFlags = <bool>[];
  final completed = <String>[];
  String? recent;
  Completer<void>? commitGate;
  bool failNextCommit = false;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async => [
    const NovelEpisodeItem(
      episodeId: _chapter,
      novelId: _work,
      sourceTid: '100',
      sourcePid: '5001',
      episodeTitle: '第一章',
      orderIndex: 0,
    ),
    const NovelEpisodeItem(
      episodeId: _next,
      novelId: _work,
      sourceTid: '100',
      sourcePid: '5002',
      episodeTitle: '下一章',
      orderIndex: 1,
    ),
  ];
  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async => NovelChapterContent(
    episodeId: episodeId,
    rawHtml: html,
    plainText: '正文',
    paragraphs: const ['正文'],
  );
  @override
  Future<NovelItem?> getDetail({required String novelId}) async => NovelItem(
    novelId: novelId,
    sourceTid: '100',
    sourceFid: '49',
    title: '测试作品',
    updatedAt: DateTime(2026, 10, 1),
    episodeCount: 2,
  );
  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async => List.of(bookmarks);
  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {
    bookmarks.add(bookmark);
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {
    bookmarks.removeWhere((bookmark) => bookmark.bookmarkId == bookmarkId);
  }

  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async => NovelReadingStateSnapshot(
    novelId: novelId,
    progressByEpisode: progress,
    episodeStates: states,
    recentEpisodeId: recent,
  );
  @override
  Future<NovelReadingProgress?> getChapterProgress({
    required String novelId,
    required String episodeId,
  }) async => progress[episodeId];
  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    final gate = commitGate;
    if (gate != null) await gate.future;
    if (failNextCommit) {
      failNextCommit = false;
      throw StateError('test progress commit failure');
    }
    if (canCommit?.call() == false) return false;
    this.progress[progress.episodeId] = progress;
    recent = progress.episodeId;
    committed.add(progress);
    commitCompletionFlags.add(markCompleted);
    if (markCompleted && states[progress.episodeId]?.isRead != true) {
      completed.add(progress.episodeId);
      states[progress.episodeId] = LibraryEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: progress.episodeId,
        workId: _work,
        isRead: true,
      );
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call: ${invocation.memberName}');
}

class _ReadingPreferences implements NovelReaderPreferencesRepository {
  NovelReaderPreferences preferences = NovelReaderPreferences.defaults()
      .copyWith(flowMode: NovelReaderFlowMode.vertical);
  @override
  Future<NovelReaderPreferences> load() async => preferences;
  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    this.preferences = preferences;
  }
}

class _DisabledDock
    implements NovelChapterInteractionsDockPreferencesRepository {
  @override
  Future<NovelChapterInteractionsDockPreferences> load() async =>
      const NovelChapterInteractionsDockPreferences(enabled: false);
  @override
  Future<void> save(
    NovelChapterInteractionsDockPreferences preferences,
  ) async {}
}

class _UnusedLibraryState implements LibraryStateRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected shared-state call: ${invocation.memberName}',
  );
}

class _PendingImageCache implements ImageCacheService {
  final requests = <ImageCacheRequest>[];
  final pending = Completer<CachedImageResult>();
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    requests.add(request);
    return pending.future;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected image-cache call: ${invocation.memberName}');
}

final class _CachedModeImage extends _PendingImageCache {
  _CachedModeImage(this.image);
  final File image;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    requests.add(request);
    return (await getCached(request.cacheKey))!;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async =>
      CachedImageResult(
        success: true,
        fromCache: true,
        cacheKey: cacheKey,
        localPath: image.path,
        width: 24,
        height: 192,
      );
}

class _SourcePostLocator implements ThreadPostLocator {
  var calls = 0;
  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    calls++;
    return ApiSuccess(ThreadPostLocation(tid: tid, pid: pid, page: 2, url: ''));
  }
}

class _SourceThreadRepository implements ThreadRepository {
  _SourceThreadRepository(this.html);
  final String html;
  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;
  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async => DataReadSuccess(
    data: ThreadDetailData(
      tid: tid,
      fid: '49',
      subject: '测试作品',
      author: 'author',
      replies: 0,
      views: 1,
      currentPage: page,
      perPage: 20,
      posts: [
        ThreadPost(
          pid: '5001',
          author: 'author',
          authorId: '10',
          message: html,
          number: 21,
          isFirst: false,
          dateline: '',
        ),
      ],
    ),
    capabilities: capabilities.toReadCapabilities(),
    metadata: const DataReadMetadata.network(),
  );
}
