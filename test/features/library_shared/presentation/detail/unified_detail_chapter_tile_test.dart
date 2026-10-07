import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_chapter_tile.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  for (final locale in <Locale>[
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
  ]) {
    testWidgets('recent percentage is localized and accessible in $locale', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpTile(
          tester,
          locale: locale,
          progress: const LibraryChapterProgressInfo(
            kind: LibraryChapterProgressKind.percentage,
            isCurrent: true,
            fraction: 0.42,
          ),
        );

        final l10n = AppLocalizations.of(tester.element(_tile));
        final label = l10n.libraryChapterLastReadPercent(42);
        expect(
          _progressText(tester).text.toPlainText(),
          '2026-10-07  ·  $label',
        );
        expect(
          tester.widget<Semantics>(_progress).properties.label,
          l10n.libraryChapterProgressSemantics('2026-10-07', label),
        );
        expect(tester.getSemantics(_progress).label, contains(label));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'non-recent progress contains percentage without last-read text',
    (tester) async {
      await _pumpTile(
        tester,
        progress: const LibraryChapterProgressInfo(
          kind: LibraryChapterProgressKind.percentage,
          isCurrent: false,
          fraction: 0.42,
        ),
      );

      final l10n = AppLocalizations.of(tester.element(_tile));
      final text = _progressText(tester).text.toPlainText();
      expect(text, '2026-10-07  ·  ${l10n.libraryChapterProgressPercent(42)}');
      expect(text, isNot(contains(l10n.libraryChapterLastRead)));
    },
  );

  testWidgets('unknown percentage with blank date has no leading separator', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpTile(
        tester,
        subtitle: '  ',
        progress: const LibraryChapterProgressInfo(
          kind: LibraryChapterProgressKind.percentage,
          isCurrent: true,
        ),
      );

      final l10n = AppLocalizations.of(tester.element(_tile));
      expect(
        _progressText(tester).text.toPlainText(),
        l10n.libraryChapterLastRead,
      );
      expect(
        tester.widget<Semantics>(_progress).properties.label,
        l10n.libraryChapterLastRead,
      );
      expect(
        tester.getSemantics(_progress).label,
        contains(l10n.libraryChapterLastRead),
      );
      expect(
        _progressText(tester).text.toPlainText(),
        isNot(contains(l10n.libraryChapterProgressPercent(0))),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('completed recent chapter is muted and omits percentage', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      isRead: true,
      progress: const LibraryChapterProgressInfo(
        kind: LibraryChapterProgressKind.percentage,
        isCurrent: true,
        fraction: 1,
      ),
    );

    final context = tester.element(_tile);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    expect(
      tester.widget<Text>(find.text(_title)).style?.color,
      scheme.onSurfaceVariant,
    );
    final text = _progressText(tester);
    expect(text.text.style?.color, scheme.onSurfaceVariant.withAlpha(170));
    expect(
      text.text.toPlainText(),
      '2026-10-07  ·  ${l10n.libraryChapterLastRead}',
    );
    expect(
      text.text.toPlainText(),
      isNot(contains(l10n.libraryChapterProgressPercent(100))),
    );
  });

  testWidgets('completed non-recent chapter keeps date without status text', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      isRead: true,
      progress: const LibraryChapterProgressInfo(
        kind: LibraryChapterProgressKind.percentage,
        isCurrent: false,
        fraction: 1,
      ),
    );

    expect(_progress, findsNothing);
    expect(find.text('2026-10-07'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('2026-10-07')).style?.color,
      Theme.of(
        tester.element(_tile),
      ).colorScheme.onSurfaceVariant.withAlpha(170),
    );
  });

  testWidgets('narrow chapter with long title respects doubled text scaling', (
    tester,
  ) async {
    const progress = LibraryChapterProgressInfo(
      kind: LibraryChapterProgressKind.percentage,
      isCurrent: true,
      fraction: 0.42,
    );
    final title = List<String>.filled(8, _title).join();
    await _pumpTile(
      tester,
      title: title,
      width: 240,
      isBookmarked: true,
      progress: progress,
    );
    final baseHeight = tester.getSize(_tile).height;
    await _pumpTile(
      tester,
      title: title,
      width: 240,
      scale: 2,
      isBookmarked: true,
      progress: progress,
    );

    expect(tester.getSize(_tile).height, greaterThan(baseHeight));
    expect(_progressText(tester).textScaler.scale(10), 20);
    expect(tester.widget<Text>(find.text(title)).maxLines, 2);
    expect(tester.getRect(_tile).contains(tester.getCenter(_progress)), isTrue);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(_tile));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.bookmark)).semanticLabel,
      l10n.libraryChapterBookmarkSemantics,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'comic page label remains a page label alongside source metadata',
    (tester) async {
      await _pumpTile(
        tester,
        subtitle: '2026-10-07  Tid:100',
        progress: const LibraryChapterProgressInfo(
          kind: LibraryChapterProgressKind.currentPage,
          isCurrent: true,
          currentPage: 3,
          totalPages: 12,
          fraction: 0.25,
        ),
      );

      final l10n = AppLocalizations.of(tester.element(_tile));
      final text = _progressText(tester).text.toPlainText();
      expect(
        text,
        '2026-10-07  Tid:100  ·  ${l10n.libraryChapterCurrentPage(3)}',
      );
      expect(text, isNot(contains(l10n.libraryChapterProgressPercent(25))));
    },
  );
}

const _title = '章节标题';
final _tile = find.byKey(const ValueKey<String>('test-chapter-tile'));
final _progress = find.byKey(
  const ValueKey<String>('unified-detail-chapter-inline-progress-episode:1'),
);

RichText _progressText(WidgetTester tester) => tester.widget<RichText>(
  find.descendant(of: _progress, matching: find.byType(RichText)),
);

Future<void> _pumpTile(
  WidgetTester tester, {
  Locale locale = const Locale('zh'),
  String title = _title,
  String subtitle = '2026-10-07',
  double width = 320,
  double scale = 1,
  bool isRead = false,
  bool isBookmarked = false,
  LibraryChapterProgressInfo? progress,
}) async {
  await tester.pumpWidget(
    LocalizedTestApp(
      locale: locale,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: UnifiedDetailChapterTile(
              tileKey: const ValueKey<String>('test-chapter-tile'),
              chapter: LibraryChapterItem(
                episodeId: 'episode:1',
                workId: 'work:1',
                title: title,
                sourceTid: '100',
                sourcePid: '5001',
                orderIndex: 0,
                isRead: isRead,
                isBookmarked: isBookmarked,
                progressInfo: progress,
              ),
              subtitle: subtitle,
              isDownloading: false,
              downloadIconSize: 20,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
