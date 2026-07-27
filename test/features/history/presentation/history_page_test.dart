import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';
import 'package:y300/features/history/presentation/controllers/history_controller.dart';
import 'package:y300/features/history/presentation/history_page.dart';
import 'package:y300/features/history/presentation/widgets/history_thumbnail.dart';

import '../test_support/history_test_support.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16, 12);

  testWidgets('renders fixture rows across responsive themes and text scales', (
    tester,
  ) async {
    final cases = <({Size size, ThemeData theme, double scale})>[
      (size: const Size(320, 700), theme: AppTheme.light(), scale: 2),
      (size: const Size(360, 760), theme: AppTheme.dark(), scale: 1.3),
      (size: const Size(900, 800), theme: AppTheme.light(), scale: 1),
    ];
    for (final testCase in cases) {
      await tester.binding.setSurfaceSize(testCase.size);
      final repository = MemoryHistoryRepository(_fixtures(now));
      final controller = buildHistoryController(repository);

      await tester.pumpWidget(
        _testApp(
          controller: controller,
          now: now,
          theme: testCase.theme,
          textScale: testCase.scale,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-page')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('history-day-今天')),
        findsOneWidget,
      );
      expect(find.text('论坛帖子'), findsOneWidget);
      expect(find.text('漫画作品'), findsOneWidget);
      expect(find.text('小说作品'), findsOneWidget);
      expect(find.byTooltip('删除记录'), findsNWidgets(3));
      final openThread = find.byKey(
        const ValueKey<String>('history-entry-open-thread:100'),
      );
      final deleteThread = find.byKey(
        const ValueKey<String>('history-entry-delete-thread:100'),
      );
      expect(
        find.descendant(of: openThread, matching: deleteThread),
        findsOneWidget,
      );
      final surface = tester.widget<Material>(
        find.byKey(const ValueKey<String>('history-entry-surface-thread:100')),
      );
      expect(surface.borderRadius, BorderRadius.circular(8));
      expect(surface.clipBehavior, Clip.antiAlias);
      expect(find.byType(Divider), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await repository.dispose();
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'opens, searches, deletes silently, and clears with confirmation',
    (tester) async {
      final repository = MemoryHistoryRepository(_fixtures(now));
      final controller = buildHistoryController(repository);
      final opened = <HistoryTargetKey>[];
      addTearDown(controller.dispose);
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        _testApp(
          controller: controller,
          now: now,
          onOpenEntry: (context, entry) async {
            opened.add(entry.target);
            return const HistoryOpenSuccess();
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('history-entry-open-thread:100')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('history-entry-open-comic:comic:1')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('history-entry-open-novel:novel:1')),
      );
      await tester.pump();
      expect(opened, const <HistoryTargetKey>[
        HistoryTargetKey(type: HistoryTargetType.thread, id: '100'),
        HistoryTargetKey(type: HistoryTargetType.comic, id: 'comic:1'),
        HistoryTargetKey(type: HistoryTargetType.novel, id: 'novel:1'),
      ]);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('history-entry-delete-comic:comic:1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('漫画作品'), findsNothing);
      expect(find.text('已删除记录'), findsNothing);
      expect(find.text('撤销'), findsNothing);

      await tester.tap(find.byKey(const Key('history-search-button')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('history-search-input')),
        '不存在',
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-search-empty')), findsOneWidget);
      expect(find.text('没有搜索结果'), findsOneWidget);

      await tester.tap(find.byKey(const Key('history-search-close')));
      await tester.pumpAndSettle();
      expect(find.text('论坛帖子'), findsOneWidget);

      await tester.tap(find.byKey(const Key('history-clear-all-button')));
      await tester.pumpAndSettle();
      expect(find.text('清空全部记录'), findsOneWidget);
      expect(find.textContaining('不会删除收藏'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('论坛帖子'), findsOneWidget);

      await tester.tap(find.byKey(const Key('history-clear-all-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.byKey(const Key('history-clear-all-button')), findsNothing);
    },
  );

  testWidgets('shows initial error and retries without replacing the page', (
    tester,
  ) async {
    final repository = MemoryHistoryRepository(_fixtures(now))
      ..failNextQuery = true;
    final controller = buildHistoryController(repository);
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    await tester.pumpWidget(_testApp(controller: controller, now: now));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-error')), findsNothing);
    expect(find.text('论坛帖子'), findsOneWidget);
  });

  testWidgets('offers source-thread recovery for a removed local work', (
    tester,
  ) async {
    final repository = MemoryHistoryRepository(_fixtures(now));
    final controller = buildHistoryController(repository);
    final opened = <HistoryTargetKey>[];
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      _testApp(
        controller: controller,
        now: now,
        onOpenEntry: (context, entry) async {
          opened.add(entry.target);
          if (entry.target.type == HistoryTargetType.comic) {
            return const HistoryOpenUnavailable(
              message: '漫画作品已从本地移除',
              fallbackTid: '000527325',
            );
          }
          return const HistoryOpenSuccess();
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('history-entry-open-comic:comic:1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('漫画作品已从本地移除'), findsOneWidget);
    expect(find.text('打开原帖'), findsOneWidget);
    expect(opened, const <HistoryTargetKey>[
      HistoryTargetKey(type: HistoryTargetType.comic, id: 'comic:1'),
    ]);

    await tester.tap(find.byType(SnackBarAction));
    await tester.pump();

    expect(opened, const <HistoryTargetKey>[
      HistoryTargetKey(type: HistoryTargetType.comic, id: 'comic:1'),
      HistoryTargetKey(type: HistoryTargetType.thread, id: '527325'),
    ]);
    expect(find.text('漫画作品'), findsOneWidget);
  });

  testWidgets('offers deleting an unavailable record without a source thread', (
    tester,
  ) async {
    final repository = MemoryHistoryRepository(_fixtures(now));
    final controller = buildHistoryController(repository);
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      _testApp(
        controller: controller,
        now: now,
        onOpenEntry: (context, entry) async {
          return const HistoryOpenUnavailable(message: '小说作品已从本地移除');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('history-entry-open-novel:novel:1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除记录'), findsOneWidget);

    await tester.tap(find.byType(SnackBarAction));
    await tester.pumpAndSettle();

    expect(find.text('小说作品'), findsNothing);
    expect(find.text('已删除记录'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('keeps search state while a reopened visit moves to the top', (
    tester,
  ) async {
    final entries = <HistoryEntry>[
      historyEntry(
        type: HistoryTargetType.comic,
        id: 'comic:newer',
        title: '漫画甲',
        visitedAt: now,
      ),
      historyEntry(
        type: HistoryTargetType.comic,
        id: 'comic:older',
        title: '漫画乙',
        visitedAt: now.subtract(const Duration(minutes: 1)),
      ),
    ];
    final repository = MemoryHistoryRepository(entries);
    final controller = buildHistoryController(repository);
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      _testApp(
        controller: controller,
        now: now,
        onOpenEntry: (context, entry) async {
          unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (routeContext) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () async {
                        await repository.recordVisit(
                          historyEntry(
                            type: entry.target.type,
                            id: entry.target.id,
                            title: entry.title,
                            visitedAt: now.add(const Duration(minutes: 1)),
                          ),
                        );
                        if (routeContext.mounted) {
                          Navigator.of(routeContext).pop();
                        }
                      },
                      child: const Text('完成访问'),
                    ),
                  ),
                ),
              ),
            ),
          );
          return const HistoryOpenSuccess();
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-search-button')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('history-search-input')), '漫画');
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('history-entry-open-comic:comic:older'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成访问'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-search-input')), findsOneWidget);
    final input = tester.widget<TextField>(
      find.byKey(const Key('history-search-input')),
    );
    expect(input.controller?.text, '漫画');
    expect(
      tester.getTopLeft(find.text('漫画乙')).dy,
      lessThan(tester.getTopLeft(find.text('漫画甲')).dy),
    );
  });
}

Widget _testApp({
  required HistoryController controller,
  required DateTime now,
  ThemeData? theme,
  double textScale = 1,
  HistoryEntryOpenCallback? onOpenEntry,
}) {
  return ProviderScope(
    child: LocalizedTestApp(
      theme: theme ?? AppTheme.light(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: HistoryPage(
        controller: controller,
        clock: _FixedHistoryClock(now),
        onOpenEntry:
            onOpenEntry ?? (context, entry) async => const HistoryOpenSuccess(),
        thumbnailBuilder: (context, entry) {
          return SizedBox(
            key: ValueKey<String>('fixture-thumbnail-${entry.target}'),
            width: HistoryThumbnail.width,
            height: HistoryThumbnail.height,
          );
        },
      ),
    ),
  );
}

List<HistoryEntry> _fixtures(DateTime now) {
  return <HistoryEntry>[
    historyEntry(
      type: HistoryTargetType.thread,
      id: '100',
      title: '论坛帖子',
      contextLabel: '综合区',
      visitedAt: now,
      page: 2,
    ),
    historyEntry(
      type: HistoryTargetType.comic,
      id: 'comic:1',
      title: '漫画作品',
      contextLabel: '第 12 话',
      visitedAt: now.subtract(const Duration(minutes: 1)),
      sourceTid: '527325',
    ),
    historyEntry(
      type: HistoryTargetType.novel,
      id: 'novel:1',
      title: '小说作品',
      contextLabel: '上次阅读',
      visitedAt: now.subtract(const Duration(minutes: 2)),
    ),
  ];
}

class _FixedHistoryClock implements HistoryClock {
  const _FixedHistoryClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
