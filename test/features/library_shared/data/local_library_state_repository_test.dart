import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('LocalLibraryStateRepository', () {
    late LocalLibraryStateRepository repository;
    const dbName = 'comic_shelf_test_library_state_repo.db';

    setUp(() async {
      await deleteDatabase(dbName);
      repository = LocalLibraryStateRepository(
        ComicLocalDb.open(databaseName: dbName),
      );
    });

    tearDown(() async {
      await deleteDatabase(dbName);
    });

    test('can upsert and query work state', () async {
      await repository.upsertWorkState(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
        lastReadEpisodeId: 'e1',
        introText: 'intro',
      );

      final state = await repository.getWorkState(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
      );

      expect(state, isNotNull);
      expect(state!.lastReadEpisodeId, 'e1');
      expect(state.introText, 'intro');
    });

    test('can upsert and count episode states', () async {
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: 'ep1',
        workId: 'novel:49:1',
        isRead: false,
        isDownloaded: true,
      );
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: 'ep2',
        workId: 'novel:49:1',
        isRead: true,
      );

      final unread = await repository.countUnreadEpisodes(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel:49:1',
      );
      final read = await repository.countReadEpisodes(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel:49:1',
      );
      final downloaded = await repository.countDownloadedEpisodes(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel:49:1',
      );

      expect(unread, 1);
      expect(read, 1);
      expect(downloaded, 1);
    });

    test('marking episode unread clears readAt', () async {
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'ep1',
        workId: 'comic:1',
        isRead: true,
        readAt: DateTime(2026, 5, 12),
      );
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'ep1',
        workId: 'comic:1',
        isRead: false,
        readAt: null,
      );

      final state = await repository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'ep1',
      );

      expect(state, isNotNull);
      expect(state!.isRead, isFalse);
      expect(state.readAt, isNull);
    });

    test('can save and load display settings', () async {
      await repository.upsertDisplaySettings(
        moduleKey: LibraryModuleKey.comic,
        displayMode: LibraryDisplayMode.grid,
        gridColumns: 2,
      );

      final settings = await repository.getDisplaySettings(
        moduleKey: LibraryModuleKey.comic,
        defaultDisplayMode: LibraryDisplayMode.grid,
      );
      expect(settings.displayMode, LibraryDisplayMode.grid);
      expect(settings.gridColumns, 2);
    });

    test('can manage tags and work binding', () async {
      final tagId = await repository.createTag(name: '待看');
      await repository.bindTagToWork(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
        tagId: tagId,
      );

      final hasAnyTag = await repository.hasAnyTag(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
      );
      final tags = await repository.getWorkTags(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
      );

      expect(hasAnyTag, isTrue);
      expect(tags.length, 1);
      expect(tags.first.name, '待看');

      await repository.unbindTagFromWork(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
        tagId: tagId,
      );
      final afterUnbind = await repository.hasAnyTag(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
      );
      expect(afterUnbind, isFalse);
    });
  });
}
