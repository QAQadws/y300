import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('work replacement retires an unfinished initial load', (
    tester,
  ) async {
    final oldHeader = Completer<LibraryDetailHeader>();
    final adapter = _PageAdapter()..headerReplies['old'] = oldHeader;
    final presented = <String>[];
    Widget page(String workId) => LocalizedTestApp(
      home: UnifiedDetailPage(
        adapter: adapter,
        workId: workId,
        onOpenReader: (_, _) async {},
        onOpenThread: (_, _) async {},
        onFirstContentPresented: (header, _) => presented.add(header.workId),
      ),
    );

    await tester.pumpWidget(page('old'));
    await tester.pump();
    await tester.pumpWidget(page('new'));
    await tester.pumpAndSettle();
    expect(find.text('title:new'), findsWidgets);
    oldHeader.completeError(StateError('retired-header'));
    await tester.pumpAndSettle();
    expect(adapter.chapterReads, ['new']);
    expect(presented, ['new']);
    expect(find.text('title:old'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adapter replacement retires refresh feedback and keeps route history guard',
    (tester) async {
      final oldAdapter = _PageAdapter();
      final newAdapter = _PageAdapter()..titlePrefix = 'replacement';
      var refreshCallbacks = 0;
      var presentations = 0;
      Widget page(_PageAdapter adapter) => LocalizedTestApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work',
          onOpenReader: (_, _) async {},
          onOpenThread: (_, _) async {},
          onRefreshCompleted: (_) async {
            refreshCallbacks++;
          },
          onFirstContentPresented: (_, _) {
            presentations++;
          },
        ),
      );

      await tester.pumpWidget(page(oldAdapter));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unified-detail-header-update')));
      await tester.pump();
      expect(oldAdapter.refreshCalls, 1);
      await tester.pumpWidget(page(newAdapter));
      await tester.pumpAndSettle();
      oldAdapter.refreshReply.complete(DetailRefreshResult.immediate);
      await tester.pumpAndSettle();
      expect(find.text('replacement:work'), findsWidgets);
      expect(oldAdapter.headerReads, ['work']);
      expect(refreshCallbacks, 0);
      expect(presentations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'presentation changes keep the same detail load and callback guard',
    (tester) async {
      final adapter = _PageAdapter();
      var presentations = 0;
      Widget page(String referer) => LocalizedTestApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work',
          imageReferer: referer,
          onOpenReader: (_, _) async {},
          onOpenThread: (_, _) async {},
          onFirstContentPresented: (_, _) {
            presentations++;
          },
        ),
      );
      await tester.pumpWidget(page('https://example.test/first'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page('https://example.test/second'));
      await tester.pumpAndSettle();
      expect(adapter.headerReads, ['work']);
      expect(adapter.chapterReads, ['work']);
      expect(presentations, 1);
    },
  );

  testWidgets('unmounting during refresh suppresses late callbacks', (
    tester,
  ) async {
    final adapter = _PageAdapter();
    var refreshCallbacks = 0;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work',
          onOpenReader: (_, _) async {},
          onOpenThread: (_, _) async {},
          onRefreshCompleted: (_) async {
            refreshCallbacks++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unified-detail-header-update')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    adapter.refreshReply.complete(DetailRefreshResult.immediate);
    await tester.pumpAndSettle();
    expect(refreshCallbacks, 0);
    expect(adapter.headerReads, ['work']);
    expect(tester.takeException(), isNull);
  });
}

class _PageAdapter implements DetailModuleAdapter {
  String titlePrefix = 'title';
  final headerReplies = <String, Completer<LibraryDetailHeader>>{};
  final headerReads = <String>[];
  final chapterReads = <String>[];
  final refreshReply = Completer<DetailRefreshResult>();
  int refreshCalls = 0;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    headerReads.add(workId);
    final reply = headerReplies[workId];
    if (reply != null) return reply.future;
    return LibraryDetailHeader(
      workId: workId,
      title: '$titlePrefix:$workId',
      inShelf: true,
    );
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    chapterReads.add(workId);
    return [
      LibraryChapterItem(
        episodeId: 'chapter',
        workId: workId,
        title: 'chapter',
        orderIndex: 0,
        isRead: false,
        isDownloaded: false,
        isBookmarked: false,
      ),
    ];
  }

  @override
  Future<DetailRefreshResult> refreshWork({required String workId}) {
    refreshCalls++;
    return refreshReply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
