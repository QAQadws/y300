import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';
import 'package:y300/features/fonts/domain/services/font_runtime_loader.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/preferences/novel_chapter_interactions_dock_preferences_provider.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_spacing.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_document_view.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reading_body_sliver.dart';

import '../../../test_support/localized_test_app.dart';
import '../../fonts/test_support/font_test_fixtures.dart';

const _work = 'novel:49:100';
const _chapter = 'novel:49:100:5001';
const _next = 'novel:49:100:5002';
const _args = NovelReaderArgs(novelId: _work, episodeId: _chapter);

void main() {
  late _Fonts fonts;
  late _FontRuntime runtime;
  late FontLibraryService fontService;
  late _NovelData novels;

  setUp(() {
    fonts = _Fonts();
    runtime = _FontRuntime();
    fontService = FontLibraryService(repository: fonts, runtimeLoader: runtime);
    novels = _NovelData();
  });

  tearDown(() async {
    fontService.dispose();
    await fonts.dispose();
  });

  testWidgets(
    'cold start waits for the selected font before publishing any body',
    (tester) async {
      final load = Completer<void>();
      runtime.gates[fonts.first.id] = load;
      final preferences = _Preferences(
        NovelReaderPreferences.defaults().copyWith(fontFamily: fonts.first.id),
      );
      await tester.pumpWidget(_app(novels, preferences, fontService));
      for (var frame = 0; frame < 100 && runtime.requested.isEmpty; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(runtime.requested, contains(fonts.first.id));
      expect(find.byType(NovelReaderHtmlPagedSurface), findsNothing);
      expect(find.byType(NovelReaderHtmlDocumentView), findsNothing);
      expect(novels.committed, isEmpty);
      load.complete();
      await _pumpReady(tester);
      final state = _state(tester);
      expect(state.bodyFont.id, fonts.first.id);
      expect(
        _surface(tester).typography.body.fontFamily,
        FontIdentity.runtimeFamily(fonts.first.id),
      );
      expect(preferences.saved, isEmpty);
      expect(novels.completed, isEmpty);
      await _close(tester);
    },
  );

  for (final mode in [
    NovelReaderFlowMode.pagedLtr,
    NovelReaderFlowMode.pagedRtl,
  ]) {
    testWidgets(
      '${mode.name} font reflow keeps the visible semantic point and saved position',
      (tester) async {
        final preferences = _Preferences(
          NovelReaderPreferences.defaults().copyWith(flowMode: mode),
        );
        await tester.pumpWidget(_app(novels, preferences, fontService));
        await _pumpReady(tester);
        for (var turn = 0; turn < 2; turn++) {
          expect(_surface(tester).navigationController!.turnNext(), isTrue);
          await tester.pumpAndSettle();
        }
        await tester.pump(const Duration(milliseconds: 300));
        final priorSurface = _surface(tester);
        final priorLayoutCount = priorSurface.paginationCache!.length;
        final anchor = priorSurface.conversionPosition!.anchor;
        expect(anchor.textOffset, greaterThan(0));
        final before = _state(tester).progressSnapshot;
        final persisted = novels.progress[_chapter];
        final load = Completer<void>();
        runtime.gates[fonts.first.id] = load;
        _controller(tester).previewPreferences(
          _state(tester).preferences.copyWith(fontFamily: fonts.first.id),
        );
        await tester.pump();
        expect(_state(tester).bodyFont.isSystem, isTrue);
        expect(
          _surface(tester).typography.body.fontFamily,
          priorSurface.typography.body.fontFamily,
        );
        load.complete();
        await _pumpReady(tester, fontId: fonts.first.id);
        final after = _surface(tester).conversionPosition!.anchor;
        expect(
          (
            after.nodeId,
            after.textOffset,
            after.formatVersion,
            after.textIdentity,
          ),
          (
            anchor.nodeId,
            anchor.textOffset,
            anchor.formatVersion,
            anchor.textIdentity,
          ),
        );
        expect(
          _snapshotFields(_state(tester).progressSnapshot),
          _snapshotFields(before),
        );
        expect(novels.progress[_chapter], same(persisted));
        expect(novels.completed, isEmpty);
        expect(
          _surface(tester).typography.body.fontFamily,
          FontIdentity.runtimeFamily(fonts.first.id),
        );
        expect(
          _surface(tester).paginationCache!.length,
          greaterThan(priorLayoutCount),
        );
        expect(_surface(tester).navigationController!.turnNext(), isTrue);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        final navigated = _state(tester).progressSnapshot;
        expect(navigated.paginationKey, isNot(before.paginationKey));
        expect((
          navigated.anchorNodeId,
          navigated.anchorTextOffset,
        ), isNot((before.anchorNodeId, before.anchorTextOffset)));
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(_state(tester).progressSnapshot, navigated);
        await _close(tester);
      },
    );
  }

  for (final format in [0, 99]) {
    testWidgets('font reflow does not migrate a stored format $format anchor', (
      tester,
    ) async {
      final saved = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        flowMode: NovelReaderFlowMode.pagedLtr,
        pageIndex: 2,
        pageCount: 20,
        progressPercent: .3,
        isProgressPercentValid: true,
        anchorNodeId: 'compatibility-node',
        anchorTextOffset: 7,
        anchorFormatVersion: format,
        anchorTextIdentity: 'stored-text-identity',
        percentBasis: NovelProgressPercentBasis.pagedStartV1,
        updatedAt: DateTime(2026, 10, 25),
      );
      novels.progress[_chapter] = saved;
      final preferences = _Preferences(NovelReaderPreferences.defaults());
      await tester.pumpWidget(_app(novels, preferences, fontService));
      await _pumpReady(tester);
      _controller(tester).previewPreferences(
        _state(tester).preferences.copyWith(fontFamily: fonts.first.id),
      );
      await _pumpReady(tester, fontId: fonts.first.id);
      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).progressSnapshot.anchorFormatVersion, format);
      expect(
        _state(tester).progressSnapshot.anchorTextIdentity,
        saved.anchorTextIdentity,
      );
      expect(novels.progress[_chapter], same(saved));
      expect(novels.committed, isEmpty);
      expect(novels.completed, isEmpty);
      await _close(tester);
      expect(novels.progress[_chapter], same(saved));
    });
  }

  testWidgets(
    'vertical font reflow preserves body geometry position without completing the chapter',
    (tester) async {
      // A single paragraph has an exact extent. Multiple lazy HTML slivers can
      // legitimately revise their estimated total after restoring the offset.
      novels = _NovelData(html: '<p>${List.filled(1000, '阅读正文').join()}。</p>');
      final preferences = _Preferences(
        NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.vertical,
        ),
      );
      await tester.pumpWidget(_app(novels, preferences, fontService));
      await _pumpReady(tester, vertical: true);
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final saved = _state(tester).progressSnapshot;
      expect(saved.progressPercent, greaterThan(0));
      expect(saved.percentBasis, NovelProgressPercentBasis.bodyGeometryV1);
      final priorCommits = novels.committed.length;
      _controller(tester).previewPreferences(
        _state(tester).preferences
            .copyWith(fontFamily: fonts.first.id, fontSize: 24),
      );
      await _pumpReady(tester, vertical: true, fontId: fonts.first.id);
      final geometry = _bodyGeometry(tester);
      final expected =
          geometry.bodyTop +
          saved.progressPercent * geometry.range -
          geometry.topChrome;
      expect(_verticalPosition(tester).pixels, closeTo(expected, 1));
      expect(
        _state(tester).progressSnapshot.progressPercent,
        saved.progressPercent,
      );
      expect(novels.committed.length, priorCommits);
      expect(novels.completed, isEmpty);
      await _close(tester);
    },
  );

  testWidgets(
    'deleting the active font falls back and repairs only the font preference',
    (tester) async {
      final preferences = _Preferences(
        NovelReaderPreferences.defaults().copyWith(fontFamily: fonts.first.id),
      );
      await tester.pumpWidget(_app(novels, preferences, fontService));
      await _pumpReady(tester, fontId: fonts.first.id);
      expect(_surface(tester).navigationController!.turnNext(), isTrue);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final before = _state(tester).progressSnapshot;
      final previous = novels.progress[_chapter];
      await tester.runAsync(() => fontService.deleteFont(fonts.first.id));
      await _pumpReady(tester, fontId: FontIdentity.system);
      await tester.pump(const Duration(milliseconds: 700));
      expect(_state(tester).bodyFont, ResolvedFont.system);
      expect(preferences.value.fontFamily, FontIdentity.system);
      expect(preferences.value.fontSize, 18.5);
      expect(
        _snapshotFields(_state(tester).progressSnapshot),
        _snapshotFields(before),
      );
      expect(novels.progress[_chapter], same(previous));
      expect(novels.completed, isEmpty);
      await _close(tester);
    },
  );

  testWidgets(
    'a failed deleted-font repair keeps a readable fallback without retry loops',
    (tester) async {
      final stored = NovelReaderPreferences.defaults().copyWith(
        fontFamily: fonts.first.id,
      );
      final preferences = _Preferences(stored)..rejectWrites = true;
      await tester.pumpWidget(_app(novels, preferences, fontService));
      await _pumpReady(tester, fontId: fonts.first.id);
      expect(_surface(tester).navigationController!.turnNext(), isTrue);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final before = _state(tester).progressSnapshot;
      final previous = novels.progress[_chapter];
      await tester.runAsync(() => fontService.deleteFont(fonts.first.id));
      await _pumpReady(tester, fontId: FontIdentity.system);
      final layouts = _surface(tester).paginationCache!.length;
      for (var interval = 0; interval < 5; interval++) {
        await tester.pump(const Duration(milliseconds: 700));
        expect(_state(tester).bodyFont, ResolvedFont.system);
        expect(_state(tester).preferences.fontFamily, FontIdentity.system);
        expect(preferences.value, same(stored));
        expect(preferences.saveAttempts, 1);
        expect(preferences.saved, isEmpty);
        expect(_surface(tester).paginationCache!.length, layouts);
        expect(
          _snapshotFields(_state(tester).progressSnapshot),
          _snapshotFields(before),
        );
      }
      expect(novels.progress[_chapter], same(previous));
      expect(novels.completed, isEmpty);
      await _close(tester);
      expect(preferences.saveAttempts, 1);
    },
  );

  testWidgets(
    'an old font load cannot alter the next chapter after a session change',
    (tester) async {
      final preferences = _Preferences(NovelReaderPreferences.defaults());
      await tester.pumpWidget(_app(novels, preferences, fontService));
      await _pumpReady(tester);
      final pending = Completer<void>();
      runtime.gates[fonts.first.id] = pending;
      _controller(tester).previewPreferences(
        _state(tester).preferences.copyWith(fontFamily: fonts.first.id),
      );
      await tester.pump();
      final navigation = _controller(tester).goToNextEpisode();
      await tester.pump();
      expect(await navigation, isTrue);
      await _pumpReady(tester);
      expect(_state(tester).currentEpisode.episodeId, _next);
      pending.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_state(tester).currentEpisode.episodeId, _next);
      expect(_state(tester).bodyFont, ResolvedFont.system);
      expect(_state(tester).preferences.fontFamily, FontIdentity.system);
      expect(preferences.saved, isEmpty);
      await _close(tester);
    },
  );
  testWidgets(
    'an unrelated catalog event cannot retire the latest pending font choice',
    (tester) async {
      final preferences = _Preferences(
        NovelReaderPreferences.defaults().copyWith(fontFamily: fonts.first.id),
      );
      await tester.pumpWidget(_app(novels, preferences, fontService));
      await _pumpReady(tester, fontId: fonts.first.id);
      final pending = Completer<void>();
      runtime.gates[fonts.second.id] = pending;
      _controller(tester).previewPreferences(
        _state(tester).preferences.copyWith(fontFamily: fonts.second.id),
      );
      await tester.pump();
      expect(runtime.requested, contains(fonts.second.id));
      fonts.announceChange();
      await tester.pump();
      expect(_state(tester).bodyFont.id, fonts.first.id);
      pending.complete();
      await _pumpReady(tester, fontId: fonts.second.id);
      expect(_state(tester).bodyFont.id, fonts.second.id);
      expect(_state(tester).preferences.fontFamily, fonts.second.id);
      expect(preferences.saved, isEmpty);
      await _close(tester);
    },
  );
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(NovelReaderPage)),
  listen: false,
);
NovelReaderViewState _state(WidgetTester tester) =>
    _container(tester).read(novelReaderControllerProvider(_args)).value!;
NovelReaderController _controller(WidgetTester tester) =>
    _container(tester).read(novelReaderControllerProvider(_args).notifier);
NovelReaderHtmlPagedSurface _surface(WidgetTester tester) =>
    tester.widget(find.byType(NovelReaderHtmlPagedSurface));

Map<String, Object?> _snapshotFields(NovelReaderProgressSnapshot value) => {
  'novelId': value.novelId,
  'episodeId': value.episodeId,
  'flowMode': value.flowMode,
  'scrollOffset': value.scrollOffset,
  'pageIndex': value.pageIndex,
  'pageCount': value.pageCount,
  'anchorNodeId': value.anchorNodeId,
  'anchorTextOffset': value.anchorTextOffset,
  'anchorFormatVersion': value.anchorFormatVersion,
  'anchorTextIdentity': value.anchorTextIdentity,
  'paginationKey': value.paginationKey,
  'progressPercent': value.progressPercent,
  'isProgressPercentValid': value.isProgressPercentValid,
  'percentBasis': value.percentBasis,
};

Future<void> _pumpReady(
  WidgetTester tester, {
  bool vertical = false,
  String? fontId,
}) async {
  for (var frame = 0; frame < 240; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final surface = find.byType(NovelReaderHtmlPagedSurface);
    final ready = vertical
        ? find
                  .byKey(const Key('novel-reader-paragraph-list'))
                  .evaluate()
                  .isNotEmpty &&
              find
                  .byKey(const Key('novel-reader-delayed-loading-surface'))
                  .evaluate()
                  .isEmpty
        : surface.evaluate().isNotEmpty &&
              _surface(tester).paginationCache!.length > 0 &&
              find
                  .byKey(const Key('novel-reader-paged-page-view'))
                  .evaluate()
                  .isNotEmpty;
    if (ready && (fontId == null || _state(tester).bodyFont.id == fontId)) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Reader with the requested font did not become ready');
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

ScrollPosition _verticalPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('novel-reader-paragraph-list')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

({double bodyTop, double range, double topChrome}) _bodyGeometry(
  WidgetTester tester,
) {
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
    range:
        body.geometry!.scrollExtent -
        (_verticalPosition(tester).viewportDimension -
            topChrome -
            bottomChrome),
    topChrome: topChrome,
  );
}

Widget _app(
  _NovelData novels,
  _Preferences preferences,
  FontLibraryService fonts,
) => ProviderScope(
  overrides: [
    novelRepositoryProvider.overrideWithValue(novels),
    novelReaderPreferencesRepositoryProvider.overrideWithValue(preferences),
    fontLibraryServiceProvider.overrideWithValue(fonts),
    novelChapterInteractionsDockPreferencesRepositoryProvider.overrideWithValue(
      _DisabledDock(),
    ),
    libraryStateRepositoryProvider.overrideWithValue(_UnusedLibraryState()),
    forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    imageCacheServiceProvider.overrideWithValue(_NoImages()),
  ],
  child: const LocalizedTestApp(
    home: NovelReaderPage(novelId: _work, initialEpisodeId: _chapter),
  ),
);

final class _Fonts implements FontLibraryRepository {
  _Fonts() {
    final payload = loadTestFont();
    first = const FontFileValidator().validate(
      fileName: 'reader.ttf',
      bytes: payload,
    );
    entries[first.id] = first;
    data[first.id] = payload;
    final otherPayload = loadTestFont(variant: 2);
    second = const FontFileValidator().validate(
      fileName: 'other.ttf',
      bytes: otherPayload,
    );
    entries[second.id] = second;
    data[second.id] = otherPayload;
  }
  late final ImportedFont first;
  late final ImportedFont second;
  final entries = <String, ImportedFont>{};
  final data = <String, Uint8List>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  void announceChange() => _changes.add(null);
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<List<ImportedFont>> listFonts() async =>
      List.unmodifiable(entries.values);
  @override
  Future<Uint8List> readFont(String fontId) async {
    final bytes = data[fontId];
    if (bytes == null) {
      throw const FontLibraryException(FontLibraryFailure.notFound);
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteFont(String fontId) async {
    entries.remove(fontId);
    data.remove(fontId);
    _changes.add(null);
  }

  @override
  Future<void> dispose() => _changes.close();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected font call: ${invocation.memberName}');
}

final class _FontRuntime implements FontRuntimeLoader {
  final gates = <String, Completer<void>>{};
  final requested = <String>[];
  @override
  Future<String> load(ImportedFont font, Uint8List bytes) async {
    requested.add(font.id);
    await gates[font.id]?.future;
    return FontIdentity.runtimeFamily(font.id);
  }
}

final class _Preferences implements NovelReaderPreferencesRepository {
  _Preferences(this.value);
  NovelReaderPreferences value;
  bool rejectWrites = false;
  int saveAttempts = 0;
  final saved = <NovelReaderPreferences>[];
  @override
  Future<NovelReaderPreferences> load() async => value;
  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    saveAttempts++;
    if (rejectWrites) throw StateError('Preference storage unavailable');
    value = preferences;
    saved.add(preferences);
  }
}

final class _NovelData implements NovelRepository, NovelReadingStateRepository {
  _NovelData({String? html})
    : html =
          html ??
          List.generate(
            18,
            (index) => '<p>第$index段：${List.filled(45, '阅读正文').join()}。</p>',
          ).join();
  final progress = <String, NovelReadingProgress>{};
  final committed = <NovelReadingProgress>[];
  final completed = <String>[];
  final states = <String, LibraryEpisodeState>{};
  final String html;
  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async => const [
    NovelEpisodeItem(
      episodeId: _chapter,
      novelId: _work,
      sourceTid: '100',
      sourcePid: '5001',
      episodeTitle: '第一章',
      orderIndex: 0,
    ),
    NovelEpisodeItem(
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
    title: '字体测试作品',
    updatedAt: DateTime(2026, 10, 25),
    episodeCount: 2,
  );
  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async => [];
  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async => NovelReadingStateSnapshot(
    novelId: novelId,
    progressByEpisode: progress,
    episodeStates: states,
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
    if (canCommit?.call() == false) return false;
    this.progress[progress.episodeId] = progress;
    committed.add(progress);
    if (markCompleted) completed.add(progress.episodeId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected novel call: ${invocation.memberName}');
}

final class _DisabledDock
    implements NovelChapterInteractionsDockPreferencesRepository {
  @override
  Future<NovelChapterInteractionsDockPreferences> load() async =>
      const NovelChapterInteractionsDockPreferences(enabled: false);
  @override
  Future<void> save(
    NovelChapterInteractionsDockPreferences preferences,
  ) async {}
}

final class _UnusedLibraryState implements LibraryStateRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected library state call: ${invocation.memberName}',
  );
}

final class _NoImages implements ImageCacheService {
  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected image call: ${invocation.memberName}');
}
