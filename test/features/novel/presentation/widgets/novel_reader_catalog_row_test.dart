import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_catalog_row.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('current, recent and bookmark projections remain independent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpRow(
        tester,
        readingState: _state(recent: 'other', bookmark: true),
        live: _live(0.63),
      );
      final tile = tester.widget<ListTile>(_tile);
      final l10n = AppLocalizations.of(tester.element(_tile));
      expect(tile.selected, isTrue);
      expect(
        (tile.subtitle as Text).data,
        l10n.libraryChapterProgressPercent(63),
      );
      expect(find.text(l10n.novelCurrent), findsOneWidget);
      expect(find.textContaining(l10n.libraryChapterLastRead), findsNothing);
      final label = tester.getSemantics(_tile).label;
      expect(
        label.split('\n').where((part) => part == l10n.novelBookmark),
        hasLength(1),
      );
      expect(
        find.byKey(const Key('novel-reader-chapter-bookmark-episode')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'unfinished saved and live end positions do not imply read completion',
    (tester) async {
      for (final recent in <String?>['episode', 'other']) {
        for (final sample in <({double fraction, int display})>[
          (fraction: 0, display: 0),
          (fraction: 0.999, display: 99),
          (fraction: 1, display: 99),
        ]) {
          for (final live in <NovelReaderProgressSnapshot?>[
            null,
            _live(sample.fraction),
          ]) {
            await _pumpRow(
              tester,
              readingState: _state(recent: recent, percent: sample.fraction),
              live: live,
            );
            final tile = tester.widget<ListTile>(_tile);
            final l10n = AppLocalizations.of(tester.element(_tile));
            expect(
              (tile.subtitle as Text).data,
              recent == 'episode'
                  ? l10n.libraryChapterLastReadPercent(sample.display)
                  : l10n.libraryChapterProgressPercent(sample.display),
            );
            expect((tile.title as Text).style?.color, isNull);
            expect(tile.selected, isTrue);
          }
        }
      }
    },
  );

  testWidgets(
    'read chapters use muted colors and omit percentage while keeping recent',
    (tester) async {
      await _pumpRow(
        tester,
        readingState: _state(read: true, percent: 1),
        live: _live(1),
      );
      final tile = tester.widget<ListTile>(_tile);
      final l10n = AppLocalizations.of(tester.element(_tile));
      final colors = Theme.of(tester.element(_tile)).colorScheme;
      expect((tile.subtitle as Text).data, l10n.libraryChapterLastRead);
      expect((tile.title as Text).style?.color, colors.onSurfaceVariant);
      expect(
        (tile.subtitle as Text).style?.color,
        colors.onSurfaceVariant.withAlpha(170),
      );
      expect(
        find.textContaining(l10n.libraryChapterProgressPercent(100)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'missing dates and unknown positions omit empty metadata and source IDs',
    (tester) async {
      await _pumpRow(tester);
      expect(tester.widget<ListTile>(_tile).subtitle, isNull);
      expect(find.textContaining('Pid:'), findsNothing);
      expect(find.textContaining('Tid:'), findsNothing);
      await _pumpRow(tester, readingState: _state(percent: 0, valid: null));
      final l10n = AppLocalizations.of(tester.element(_tile));
      expect(
        (tester.widget<ListTile>(_tile).subtitle as Text).data,
        l10n.libraryChapterLastRead,
      );
    },
  );

  testWidgets('partial current position hides a stale percentage', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      readingState: _state(),
      live: _live(0, valid: false),
    );
    final l10n = AppLocalizations.of(tester.element(_tile));
    expect(
      (tester.widget<ListTile>(_tile).subtitle as Text).data,
      l10n.libraryChapterLastRead,
    );
  });

  testWidgets('long titles fit a narrow catalog with doubled text scaling', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      readingState: _state(bookmark: true),
      width: 280,
      scale: 2,
      title: List.filled(20, '很长的章节名').join(),
      date: '2026-10-07 01:03',
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(_tile).height, greaterThan(72));
    expect((tester.widget<ListTile>(_tile).subtitle as Text).maxLines, 2);
  });

  testWidgets(
    'the shared physical right swipe triggers once while an action is running',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await _pumpRow(
        tester,
        onToggle: () {
          calls++;
          return pending.future;
        },
      );
      await tester.drag(_tile, const Offset(300, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, 1);
      await tester.drag(_tile, const Offset(300, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('externally locked and reverse swipes do not change state', (
    tester,
  ) async {
    var calls = 0;
    Future<void> toggle() async => calls++;
    await _pumpRow(tester, onToggle: toggle, locked: true);
    await tester.drag(_tile, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await _pumpRow(tester, onToggle: toggle);
    await tester.drag(_tile, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}

final _tile = find.byKey(const Key('novel-reader-chapter-episode'));

NovelReadingStateSnapshot _state({
  String? recent = 'episode',
  bool read = false,
  bool bookmark = false,
  double percent = 0.42,
  bool? valid = true,
}) => NovelReadingStateSnapshot(
  novelId: 'novel',
  recentEpisodeId: recent,
  progressByEpisode: {
    'episode': NovelReadingProgress(
      novelId: 'novel',
      episodeId: 'episode',
      scrollOffset: 80,
      progressPercent: percent,
      isProgressPercentValid: valid,
      updatedAt: DateTime(2026, 10, 7),
    ),
  },
  episodeStates: {
    'episode': LibraryEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      workId: 'novel',
      episodeId: 'episode',
      isRead: read,
      isBookmarked: bookmark,
    ),
  },
);

NovelReaderProgressSnapshot _live(double percent, {bool valid = true}) =>
    NovelReaderProgressSnapshot(
      novelId: 'novel',
      episodeId: 'episode',
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: 80,
      pageIndex: 0,
      progressPercent: percent,
      isProgressPercentValid: valid,
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  NovelReadingStateSnapshot? readingState,
  NovelReaderProgressSnapshot? live,
  double width = 320,
  double scale = 1,
  String title = 'Chapter',
  String? date,
  Future<void> Function()? onToggle,
  bool locked = false,
}) async {
  await tester.pumpWidget(
    LocalizedTestApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: SizedBox(
              width: width,
              child: NovelReaderCatalogRow(
                episode: NovelEpisodeItem(
                  novelId: 'novel',
                  episodeId: 'episode',
                  sourceTid: '100',
                  sourcePid: '5001',
                  orderIndex: 0,
                  episodeTitle: title,
                  datelineText: date,
                ),
                currentEpisodeId: 'episode',
                readingState: readingState,
                progressSnapshot: live,
                onTap: () {},
                onToggleReadState: onToggle,
                readStateMutationLocked: locked,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
