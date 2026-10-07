import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'live progress and the retained last-read chapter are independent',
    (tester) async {
      await _pumpCatalog(
        tester,
        _viewState(
          readingProgress: _savedProgress(episodeIndex: 1, percent: 0.42),
          snapshot: _snapshot(percent: 0.63),
        ),
      );
      final l10n = _l10n(tester);

      expect(
        _subtitle(tester, 0),
        contains(l10n.libraryChapterProgressPercent(63)),
      );
      expect(
        _subtitle(tester, 1),
        contains(l10n.libraryChapterLastReadPercent(42)),
      );
      expect(tester.widget<ListTile>(_tile(0)).selected, isTrue);
      expect(tester.widget<ListTile>(_tile(1)).selected, isFalse);
      expect(find.text(l10n.novelCurrent), findsOneWidget);
      expect(find.textContaining('Pid:'), findsNothing);
      expect(find.textContaining('Tid:'), findsNothing);
    },
  );

  testWidgets('current, last-read and bookmark states coexist with no date', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCatalog(
        tester,
        _viewState(
          readingProgress: _savedProgress(percent: 0.42),
          snapshot: _snapshot(percent: 0.63),
          date: '  ',
          bookmarked: true,
        ),
      );
      final l10n = _l10n(tester);

      expect(_subtitle(tester, 0), l10n.libraryChapterLastReadPercent(63));
      expect(find.text(l10n.novelCurrent), findsOneWidget);
      expect(
        find.byKey(Key('novel-reader-chapter-bookmark-${_episodeId(0)}')),
        findsOneWidget,
      );
      final label = tester.getSemantics(_tile(0)).label;
      expect(
        label.split('\n').where((part) => part == l10n.novelBookmark),
        hasLength(1),
      );
      expect(label, contains(l10n.novelCurrent));
      expect(find.text(l10n.novelBookmark), findsNothing);
      expect(tester.widget<ListTile>(_tile(0)).selected, isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('partial live pagination suppresses a stale saved percentage', (
    tester,
  ) async {
    await _pumpCatalog(
      tester,
      _viewState(
        readingProgress: _savedProgress(percent: 0.42),
        snapshot: _snapshot(percent: 0, valid: false),
        date: null,
      ),
    );
    final l10n = _l10n(tester);

    expect(_subtitle(tester, 0), l10n.libraryChapterLastRead);
    expect(
      find.textContaining(l10n.libraryChapterProgressPercent(0)),
      findsNothing,
    );
    expect(
      find.textContaining(l10n.libraryChapterProgressPercent(42)),
      findsNothing,
    );
  });

  testWidgets(
    'bootstrap zero is hidden but an explicitly valid zero is shown',
    (tester) async {
      await _pumpCatalog(tester, _viewState(date: null));
      final l10n = _l10n(tester);
      expect(tester.widget<ListTile>(_tile(0)).subtitle, isNull);

      await _pumpCatalog(
        tester,
        _viewState(snapshot: _snapshot(percent: 0, valid: true), date: null),
      );
      expect(_subtitle(tester, 0), l10n.libraryChapterProgressPercent(0));
      expect(find.textContaining(l10n.libraryChapterLastRead), findsNothing);
    },
  );

  testWidgets('unknown saved zero keeps only the last-read marker', (
    tester,
  ) async {
    await _pumpCatalog(
      tester,
      _viewState(readingProgress: _savedProgress(percent: 0), date: null),
    );
    expect(_subtitle(tester, 0), _l10n(tester).libraryChapterLastRead);
  });

  testWidgets('long titles and progress fit a narrow scaled catalog', (
    tester,
  ) async {
    await _pumpCatalog(
      tester,
      _viewState(
        readingProgress: _savedProgress(percent: 0.42),
        snapshot: _snapshot(percent: 0.42),
        bookmarked: true,
        title: List.filled(20, '目录中很长的章节名称').join(),
      ),
      width: 280,
      textScale: 2,
    );
    final l10n = _l10n(tester);
    expect(
      _subtitle(tester, 0),
      contains(l10n.libraryChapterLastReadPercent(42)),
    );
    expect(find.text(l10n.novelCurrent), findsOneWidget);
    expect(tester.getSize(_tile(0)).height, greaterThan(72));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the displayed progress does not move following rows', (
    tester,
  ) async {
    await _pumpCatalog(tester, _viewState());
    final before = tester.getTopLeft(_tile(1));

    await _pumpCatalog(
      tester,
      _viewState(
        readingProgress: _savedProgress(percent: 0.42),
        snapshot: _snapshot(percent: 0.42),
      ),
    );

    expect(tester.getTopLeft(_tile(1)), before);
    expect(tester.takeException(), isNull);
  });
}

const _novelId = 'novel:49:100';

String _episodeId(int index) => '$_novelId:${5001 + index}';

Finder _tile(int index) =>
    find.byKey(Key('novel-reader-chapter-${_episodeId(index)}'));

String? _subtitle(WidgetTester tester, int index) =>
    (tester.widget<ListTile>(_tile(index)).subtitle as Text?)?.data;

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(NovelReaderChapterListSheet)),
);

NovelReadingProgress _savedProgress({
  int episodeIndex = 0,
  required double percent,
}) => NovelReadingProgress(
  novelId: _novelId,
  episodeId: _episodeId(episodeIndex),
  scrollOffset: 120,
  updatedAt: DateTime(2026, 10, 7),
  progressPercent: percent,
);

NovelReaderProgressSnapshot _snapshot({required double percent, bool? valid}) =>
    NovelReaderProgressSnapshot(
      novelId: _novelId,
      episodeId: _episodeId(0),
      flowMode: valid == false
          ? NovelReaderFlowMode.pagedLtr
          : NovelReaderFlowMode.vertical,
      scrollOffset: percent > 0 ? 120 : 0,
      pageIndex: 0,
      progressPercent: percent,
      isProgressPercentValid: valid,
    );

NovelReaderViewState _viewState({
  NovelReadingProgress? readingProgress,
  NovelReaderProgressSnapshot? snapshot,
  String? date = '2026-10-07 01:03',
  String? title,
  bool bookmarked = false,
}) {
  final episodes = List<NovelEpisodeItem>.generate(
    3,
    (index) => NovelEpisodeItem(
      episodeId: _episodeId(index),
      novelId: _novelId,
      sourceTid: '100',
      sourcePid: '${5001 + index}',
      episodeTitle: title ?? '章节 ${index + 1}',
      orderIndex: index,
      datelineText: date,
    ),
  );
  final preferences = NovelReaderPreferences.defaults();
  return NovelReaderViewState(
    novel: null,
    episodes: episodes,
    currentEpisode: episodes.first,
    currentContent: NovelChapterContent(
      episodeId: episodes.first.episodeId,
      rawHtml: '<p>正文</p>',
      plainText: '正文',
      paragraphs: const ['正文'],
    ),
    document: NovelReaderDocument(
      episodeId: episodes.first.episodeId,
      rawHtmlHash: 'catalog-progress',
      body: RichDocument.empty,
      plainText: '正文',
      wordCount: 2,
    ),
    persistedPreferences: preferences,
    effectivePreferences: preferences,
    readingProgress: readingProgress,
    progressSnapshot: snapshot ?? _snapshot(percent: 0),
    currentOffset: snapshot?.scrollOffset ?? 0,
    bookmarks: [
      if (bookmarked)
        NovelReaderBookmark(
          bookmarkId: 'episode-bookmark:${episodes.first.episodeId}',
          novelId: _novelId,
          episodeId: episodes.first.episodeId,
          anchor: NovelReaderTextAnchor(episodeId: episodes.first.episodeId),
          title: episodes.first.episodeTitle,
          snippet: '正文',
          createdAt: DateTime(2026, 10, 7),
          updatedAt: DateTime(2026, 10, 7),
        ),
    ],
  );
}

Future<void> _pumpCatalog(
  WidgetTester tester,
  NovelReaderViewState viewState, {
  double width = 320,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 740);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LocalizedTestApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: NovelReaderChapterListSheet(viewState: viewState),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
