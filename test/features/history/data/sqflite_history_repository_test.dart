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
      'v1 retains existing entries while round-tripping blog snapshots',
      () async {
        for (final type in [
          HistoryTargetType.thread,
          HistoryTargetType.comic,
          HistoryTargetType.novel,
        ]) {
          await repository.recordVisit(
            _entry(type: type, id: '100', title: type.name, at: _time(1)),
          );
        }
        repository.dispose();
        await db.close();

        final reopened = HistoryLocalDb.open(databaseName: dbName);
        db = await reopened;
        repository = SqfliteHistoryRepository(reopened);
        final blog = _entry(
          type: HistoryTargetType.blog,
          id: '101:100',
          title: '日志标题',
          contextLabel: '作者原名',
          at: _time(2),
          page: 3,
          canonicalUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&uid=101&do=blog&id=100',
          ),
          thumbnail: const HistoryThumbnailSnapshot(
            remoteUrl: 'https://bbs.yamibo.com/data/attachment/blog/cover.jpg',
          ),
        );
        await repository.recordVisit(blog);
        repository.dispose();
        await db.close();

        final reopenedWithBlog = HistoryLocalDb.open(databaseName: dbName);
        db = await reopenedWithBlog;
        repository = SqfliteHistoryRepository(reopenedWithBlog);
        final entries = (await repository.query(const HistoryQuery())).items;

        expect(await db.getVersion(), 1);
        expect(entries, hasLength(4));
        expect(entries.first, blog);
        expect(entries.skip(1).map((entry) => entry.target.type).toSet(), {
          HistoryTargetType.thread,
          HistoryTargetType.comic,
          HistoryTargetType.novel,
        });
      },
    );

    test(
      'blog visits aggregate, search by author and keep ordinary lifecycle',
      () async {
        final first = _entry(
          type: HistoryTargetType.blog,
          id: '101:23',
          title: '旧标题',
          contextLabel: '原作者',
          at: _time(1),
        );
        await repository.recordVisit(first);
        await repository.recordVisit(
          _entry(
            target: first.target,
            title: '新标题',
            contextLabel: '原作者',
            at: _time(3),
          ),
        );
        await repository.recordVisit(
          _entry(
            type: HistoryTargetType.blog,
            id: '102:23',
            title: '另一作者日志',
            contextLabel: '另一作者',
            at: _time(2),
          ),
        );

        final found = (await repository.query(
          const HistoryQuery(searchText: '原作者'),
        )).items.single;
        expect(found.target, first.target);
        expect(found.title, '新标题');
        expect(found.visitCount, 2);
        expect(found.firstVisitedAt, _time(1));
        expect(found.lastVisitedAt, _time(3));
        expect(
          (await repository.query(const HistoryQuery())).items.first,
          found,
        );

        await repository.delete(found.target);
        expect(
          (await repository.query(const HistoryQuery(searchText: '原作者'))).items,
          isEmpty,
        );
        await repository.restore(found);
        expect(
          (await repository.query(const HistoryQuery())).items.first,
          found,
        );
        await repository.clear();
        expect((await repository.query(const HistoryQuery())).items, isEmpty);
      },
    );

    test('blog entries participate in the shared retention limit', () async {
      final retained = SqfliteHistoryRepository(
        Future<Database>.value(db),
        retentionPolicy: const HistoryRetentionPolicy(maxEntries: 2),
      );
      addTearDown(retained.dispose);
      await retained.recordVisit(
        _entry(
          type: HistoryTargetType.blog,
          id: '101:23',
          title: '较早日志',
          at: _time(1),
        ),
      );
      await retained.recordVisit(
        _entry(
          type: HistoryTargetType.thread,
          id: '23',
          title: '帖子',
          at: _time(2),
        ),
      );
      await retained.recordVisit(
        _entry(
          type: HistoryTargetType.blog,
          id: '101:24',
          title: '较新日志',
          at: _time(3),
        ),
      );

      expect(
        (await retained.query(
          const HistoryQuery(),
        )).items.map((entry) => entry.target.id),
        ['101:24', '23'],
      );
    });

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

    test('keeps target types separate for the same stored id', () async {
      for (final type in HistoryTargetType.values) {
        await repository.recordVisit(
          _entry(type: type, id: '100', title: type.name, at: _time(1)),
        );
      }

      final page = await repository.query(const HistoryQuery());

      expect(page.items, hasLength(4));
      expect(page.items.map((entry) => entry.target.type).toSet(), {
        HistoryTargetType.thread,
        HistoryTargetType.comic,
        HistoryTargetType.novel,
        HistoryTargetType.blog,
      });
    });

    test(
      'late writes increment visits without replacing the newer snapshot',
      () async {
        const target = HistoryTargetKey(
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
        const target = HistoryTargetKey(
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

    test(
      'queries, searches, and paginates 2000 entries without blocking',
      () async {
        const mapper = HistoryRowMapper();
        final base = DateTime.utc(2026, 7, 1);
        final batch = db.batch();
        for (var index = 0; index < 2000; index++) {
          final title = index == 1379 ? 'needle history entry' : '帖子 $index';
          batch.insert(
            HistoryLocalDb.entriesTable,
            mapper.toRow(
              _entry(
                type: HistoryTargetType.thread,
                id: '${index + 1}',
                title: title,
                at: base.add(Duration(milliseconds: index)),
              ),
            ),
          );
        }
        await batch.commit(noResult: true);

        final firstPageWatch = Stopwatch()..start();
        final firstPage = await repository.query(const HistoryQuery(limit: 50));
        firstPageWatch.stop();
        final secondPage = await repository.query(
          HistoryQuery(cursor: firstPage.nextCursor, limit: 50),
        );
        final searchWatch = Stopwatch()..start();
        final searchPage = await repository.query(
          const HistoryQuery(searchText: 'needle history entry', limit: 50),
        );
        searchWatch.stop();

        expect(firstPage.items, hasLength(50));
        expect(firstPage.hasMore, isTrue);
        expect(secondPage.items, hasLength(50));
        expect(
          firstPage.items
              .map((entry) => entry.target)
              .toSet()
              .intersection(
                secondPage.items.map((entry) => entry.target).toSet(),
              ),
          isEmpty,
        );
        expect(searchPage.items.single.title, 'needle history entry');
        expect(firstPageWatch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(searchWatch.elapsed, lessThan(const Duration(seconds: 5)));
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
    HistoryTargetType.blog => HistoryVisitSurface.blogDetail,
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
