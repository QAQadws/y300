import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Database;
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('providers accept database name and clock overrides', () async {
    const dbName = 'history_records_phase1_provider_test.db';
    await deleteDatabase(dbName);
    final now = DateTime.utc(2026, 7, 16, 20, 30);
    final container = ProviderContainer(
      overrides: [
        historyDatabaseNameProvider.overrideWithValue(dbName),
        historyClockProvider.overrideWithValue(_FixedHistoryClock(now)),
      ],
    );

    await container
        .read(recordHistoryVisitUseCaseProvider)
        .call(
          const HistoryVisitDraft(
            target: HistoryTargetKey(type: HistoryTargetType.thread, id: '100'),
            surface: HistoryVisitSurface.threadNative,
            title: '测试帖子',
          ),
        );
    final page = await container
        .read(queryHistoryUseCaseProvider)
        .call(const HistoryQuery());

    expect(page.items.single.lastVisitedAt, now);
    final manager = container.read(historyDatabaseManagerProvider);
    final db = await container.read(historyDatabaseProvider);
    container.dispose();
    await manager.dispose();
    expect(db.isOpen, isFalse);
    await deleteDatabase(dbName);
  });

  test('record use case follows repository provider override', () async {
    final repository = _RecordingHistoryRepository();
    final now = DateTime.utc(2026, 7, 16, 21);
    final container = ProviderContainer(
      overrides: [
        historyRepositoryProvider.overrideWithValue(repository),
        historyClockProvider.overrideWithValue(_FixedHistoryClock(now)),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(recordHistoryVisitUseCaseProvider)
        .call(
          const HistoryVisitDraft(
            target: HistoryTargetKey(
              type: HistoryTargetType.comic,
              id: 'comic:1',
            ),
            surface: HistoryVisitSurface.comicDetail,
            title: '  漫画标题  ',
          ),
        );

    expect(repository.recorded, hasLength(1));
    expect(repository.recorded.single.title, '漫画标题');
    expect(repository.recorded.single.lastVisitedAt, now);
  });
}

class _FixedHistoryClock implements HistoryClock {
  const _FixedHistoryClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

class _RecordingHistoryRepository implements HistoryRepository {
  final List<HistoryEntry> recorded = <HistoryEntry>[];
  final StreamController<HistoryChange> _changes =
      StreamController<HistoryChange>.broadcast();

  @override
  Future<void> recordVisit(HistoryEntry candidate) async {
    recorded.add(candidate);
  }

  @override
  Future<void> clear() async {}

  @override
  Future<void> delete(HistoryTargetKey target) async {}

  @override
  Future<HistoryQueryPage> query(HistoryQuery query) async {
    return const HistoryQueryPage(items: <HistoryEntry>[], hasMore: false);
  }

  @override
  Future<void> restore(HistoryEntry entry) async {}

  @override
  Stream<HistoryChange> watchChanges() => _changes.stream;
}
