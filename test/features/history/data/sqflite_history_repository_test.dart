import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Database;
import 'package:y300/features/history/data/local/history_local_db.dart';
import 'package:y300/features/history/data/local/history_row_mapper.dart';
import 'package:y300/features/history/data/repositories/sqflite_history_repository.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_retention_policy.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SqfliteHistoryRepository', () {
    const dbName = 'history_records_phase1_repository_test.db';
    late Database db;
    late SqfliteHistoryRepository repository;

    setUp(() async {
      await deleteDatabase(dbName);
      final database = HistoryLocalDb.open(databaseName: dbName);
      db = await database;
      repository = SqfliteHistoryRepository(database);
    });

    tearDown(() async {
      repository.dispose();
      if (db.isOpen) {
        await db.close();
      }
      await deleteDatabase(dbName);
    });

    test(
      'v1 schema persists an inserted entry after database reopen',
      () async {
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        final indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index'",
        );
        expect(
          tables.map((row) => row['name']),
          contains(HistoryLocalDb.entriesTable),
        );
        expect(
          indexes.map((row) => row['name']),
          contains(HistoryLocalDb.recentIndex),
        );

        final saved = _entry(
          type: HistoryTargetType.thread,
          id: '100',
          title: '持久化帖子',
          at: _time(1),
        );
        await repository.recordVisit(saved);
        repository.dispose();
        await db.close();

        final reopenedFuture = HistoryLocalDb.open(databaseName: dbName);
        db = await reopenedFuture;
        repository = SqfliteHistoryRepository(reopenedFuture);
        final page = await repository.query(const HistoryQuery());

        expect(page.items, <HistoryEntry>[saved]);
      },
    );

    test(
      'upserts the same target and moves its latest visit to the top',
      () async {
        await repository.recordVisit(
          _entry(
            type: HistoryTargetType.thread,
            id: '100',
            title: '旧标题',
            at: _time(1),
          ),
        );
        await repository.recordVisit(
          _entry(
            type: HistoryTargetType.comic,
            id: 'comic:1',
            title: '漫画',
            at: _time(2),
          ),
        );
        await repository.recordVisit(
          _entry(
            type: HistoryTargetType.thread,
            id: '100',
            title: '新标题',
            at: _time(3),
          ),
        );

        final items = (await repository.query(const HistoryQuery())).items;

        expect(items.map((entry) => entry.title), <String>['新标题', '漫画']);
        expect(items.first.visitCount, 2);
        expect(items.first.firstVisitedAt, _time(1));
        expect(items.first.lastVisitedAt, _time(3));
      },
    );

    test(
      'keeps thread, comic and novel identities separate for the same id',
      () async {
        for (final type in HistoryTargetType.values) {
          await repository.recordVisit(
            _entry(type: type, id: '100', title: type.name, at: _time(1)),
          );
        }

        final page = await repository.query(const HistoryQuery());

        expect(page.items, hasLength(3));
        expect(page.items.map((entry) => entry.target.type).toSet(), {
          HistoryTargetType.thread,
          HistoryTargetType.comic,
          HistoryTargetType.novel,
        });
      },
    );

    test(
      'late writes increment visits without replacing the newer snapshot',
      () async {
        final target = const HistoryTargetKey(
          type: HistoryTargetType.thread,
          id: '100',
        );
        await repository.recordVisit(
          _entry(
            target: target,
            title: '较新标题',
            contextLabel: '较新版块',
            at: _time(5),
            page: 5,
          ),
        );
        await repository.recordVisit(
          _entry(
            target: target,
            title: '迟到旧标题',
            contextLabel: '旧版块',
            at: _time(2),
            page: 2,
          ),
        );

        final entry = (await repository.query(
          const HistoryQuery(),
        )).items.single;

        expect(entry.title, '较新标题');
        expect(entry.contextLabel, '较新版块');
        expect(entry.lastPage, 5);
        expect(entry.firstVisitedAt, _time(2));
        expect(entry.lastVisitedAt, _time(5));
        expect(entry.visitCount, 2);
      },
    );

    test(
      'newer sparse snapshots preserve optional cover and route fields',
      () async {
        final target = const HistoryTargetKey(
          type: HistoryTargetType.comic,
          id: 'comic:1',
        );
        await repository.recordVisit(
          _entry(
            target: target,
            title: '完整快照',
            at: _time(1),
            thumbnail: const HistoryThumbnailSnapshot(
              localPath: 'C:/cover.jpg',
              remoteUrl: 'https://example.com/cover.jpg',
              focusX: 0.25,
              focusY: 0.75,
            ),
            sourceTid: '100',
            canonicalUri: Uri.parse(
              'https://bbs.yamibo.com/thread-100-1-1.html',
            ),
            forumName: '漫画区',
          ),
        );
        await repository.recordVisit(
          _entry(target: target, title: '更新标题', at: _time(2)),
        );

        final entry = (await repository.query(
          const HistoryQuery(),
        )).items.single;

        expect(entry.title, '更新标题');
        expect(entry.thumbnail?.localPath, 'C:/cover.jpg');
        expect(entry.thumbnail?.remoteUrl, 'https://example.com/cover.jpg');
        expect(entry.thumbnail?.focusX, 0.25);
        expect(entry.sourceTid, '100');
        expect(
          entry.canonicalUri.toString(),
          'https://bbs.yamibo.com/thread-100-1-1.html',
        );
        expect(entry.forumName, '漫画区');
      },
    );

    test(
      'delete, restore and clear publish changes only after mutations',
      () async {
        final changes = <HistoryChange>[];
        final subscription = repository.watchChanges().listen(changes.add);
        addTearDown(subscription.cancel);
        final original = _entry(
          type: HistoryTargetType.novel,
          id: 'novel:1',
          title: '原记录',
          at: _time(1),
        );

        await repository.recordVisit(original);
        await repository.delete(original.target);
        expect((await repository.query(const HistoryQuery())).items, isEmpty);
        await repository.restore(original);
        expect(
          (await repository.query(const HistoryQuery())).items.single,
          original,
        );

        final newer = _entry(
          target: original.target,
          title: '更新后的记录',
          at: _time(2),
        );
        await repository.recordVisit(newer);
        await repository.restore(original);
        await repository.delete(
          const HistoryTargetKey(type: HistoryTargetType.thread, id: 'missing'),
        );
        expect(
          (await repository.query(const HistoryQuery())).items.single.title,
          '更新后的记录',
        );

        await repository.clear();
        await repository.clear();

        expect(changes.map((change) => change.kind), <HistoryChangeKind>[
          HistoryChangeKind.recorded,
          HistoryChangeKind.deleted,
          HistoryChangeKind.restored,
          HistoryChangeKind.recorded,
          HistoryChangeKind.cleared,
        ]);
      },
    );

    test(r'search treats %, _ and \ as literal characters', () async {
      final titles = <String>[
        '100% pure',
        'under_score',
        r'back\slash',
        'ordinary',
      ];
      for (var index = 0; index < titles.length; index++) {
        await repository.recordVisit(
          _entry(
            type: HistoryTargetType.comic,
            id: 'comic:$index',
            title: titles[index],
            at: _time(index),
          ),
        );
      }

      expect(
        (await repository.query(
          const HistoryQuery(searchText: '%'),
        )).items.single.title,
        '100% pure',
      );
      expect(
        (await repository.query(
          const HistoryQuery(searchText: '_'),
        )).items.single.title,
        'under_score',
      );
      expect(
        (await repository.query(
          const HistoryQuery(searchText: r'\'),
        )).items.single.title,
        r'back\slash',
      );
    });

    test('keyset cursor is stable when all timestamps are identical', () async {
      final at = _time(1);
      final targets = <HistoryTargetKey>[
        const HistoryTargetKey(type: HistoryTargetType.thread, id: '2'),
        const HistoryTargetKey(type: HistoryTargetType.comic, id: '2'),
        const HistoryTargetKey(type: HistoryTargetType.novel, id: '1'),
        const HistoryTargetKey(type: HistoryTargetType.comic, id: '1'),
        const HistoryTargetKey(type: HistoryTargetType.thread, id: '1'),
      ];
      for (final target in targets) {
        await repository.recordVisit(
          _entry(target: target, title: target.toString(), at: at),
        );
      }

      final collected = <HistoryTargetKey>[];
      HistoryCursor? cursor;
      do {
        final page = await repository.query(
          HistoryQuery(cursor: cursor, limit: 2),
        );
        collected.addAll(page.items.map((entry) => entry.target));
        cursor = page.nextCursor;
      } while (cursor != null);

      expect(collected, <HistoryTargetKey>[
        const HistoryTargetKey(type: HistoryTargetType.comic, id: '1'),
        const HistoryTargetKey(type: HistoryTargetType.comic, id: '2'),
        const HistoryTargetKey(type: HistoryTargetType.novel, id: '1'),
        const HistoryTargetKey(type: HistoryTargetType.thread, id: '1'),
        const HistoryTargetKey(type: HistoryTargetType.thread, id: '2'),
      ]);
      expect(collected.toSet(), hasLength(5));
    });

    test(
      'retention keeps only the configured most recent unique targets',
      () async {
        final retainedRepository = SqfliteHistoryRepository(
          Future<Database>.value(db),
          retentionPolicy: const HistoryRetentionPolicy(maxEntries: 3),
        );
        addTearDown(retainedRepository.dispose);
        for (var index = 0; index < 5; index++) {
          await retainedRepository.recordVisit(
            _entry(
              type: HistoryTargetType.thread,
              id: '${index + 1}',
              title: '帖子 ${index + 1}',
              at: _time(index),
            ),
          );
        }

        final items = (await retainedRepository.query(
          const HistoryQuery(),
        )).items;

        expect(items.map((entry) => entry.target.id), <String>['5', '4', '3']);
      },
    );

    test('row mapper rejects unknown persisted enum values', () {
      const mapper = HistoryRowMapper();
      final row = mapper.toRow(
        _entry(
          type: HistoryTargetType.thread,
          id: '100',
          title: '帖子',
          at: _time(1),
        ),
      )..['target_type'] = 'reader';

      expect(() => mapper.fromRow(row), throwsFormatException);
    });
  });
}

DateTime _time(int minute) => DateTime.utc(2026, 7, 16, 12, minute);

HistoryEntry _entry({
  HistoryTargetKey? target,
  HistoryTargetType? type,
  String? id,
  required String title,
  required DateTime at,
  String contextLabel = '详情',
  HistoryThumbnailSnapshot? thumbnail,
  String? sourceTid,
  Uri? canonicalUri,
  int? page,
  String? forumName,
}) {
  final resolvedTarget = target ?? HistoryTargetKey(type: type!, id: id!);
  final surface = switch (resolvedTarget.type) {
    HistoryTargetType.thread => HistoryVisitSurface.threadNative,
    HistoryTargetType.comic => HistoryVisitSurface.comicDetail,
    HistoryTargetType.novel => HistoryVisitSurface.novelDetail,
  };
  return HistoryEntry(
    target: resolvedTarget,
    title: title,
    contextLabel: contextLabel,
    thumbnail: thumbnail,
    sourceTid: sourceTid,
    canonicalUri: canonicalUri,
    lastPage: page,
    forumName: forumName,
    lastSurface: surface,
    firstVisitedAt: at,
    lastVisitedAt: at,
    visitCount: 1,
  );
}
