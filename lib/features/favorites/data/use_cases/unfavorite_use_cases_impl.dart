import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/services/favorite_link_service.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/work_purge_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

class DefaultUnfavoriteWorkUseCase implements UnfavoriteWorkUseCase {
  const DefaultUnfavoriteWorkUseCase({
    required FavoriteThreadCommand favoriteThreadCommand,
    required FavoriteLinkService favoriteLinkService,
    required LocalFavoriteRepository localFavoriteRepository,
    required WorkPurgeService workPurgeService,
    required LibraryShelfRefreshBus shelfRefreshBus,
  }) : _favoriteThreadCommand = favoriteThreadCommand,
       _favoriteLinkService = favoriteLinkService,
       _localFavoriteRepository = localFavoriteRepository,
       _workPurgeService = workPurgeService,
       _shelfRefreshBus = shelfRefreshBus;

  final FavoriteThreadCommand _favoriteThreadCommand;
  final FavoriteLinkService _favoriteLinkService;
  final LocalFavoriteRepository _localFavoriteRepository;
  final WorkPurgeService _workPurgeService;
  final LibraryShelfRefreshBus _shelfRefreshBus;

  @override
  Future<UnfavoriteResult> call({
    required String workId,
    required ThreadContentKind kind,
  }) async {
    final normalizedWorkId = workId.trim();
    if (normalizedWorkId.isEmpty) {
      throw ArgumentError('workId must not be empty');
    }

    final links = await _favoriteLinkService.linksForWork(normalizedWorkId);
    if (links.threads.isEmpty) {
      return const UnfavoriteResult(
        requestedTids: <String>[],
        succeededTids: <String>[],
        failedTids: <String>[],
        purgedWorkIds: <String>[],
      );
    }

    final requestedTids = links.tids;
    final succeededTids = <String>[];
    final failedTids = <String>[];

    for (final tid in requestedTids) {
      final result = await _favoriteThreadCommand.execute(
        SetThreadFavoriteRequest(
          tid: tid,
          targetState: FavoriteTargetState.unfavorited,
        ),
      );
      if (result case DataCommandApplied<ThreadFavoriteReceipt>()) {
        succeededTids.add(tid);
      } else {
        failedTids.add(tid);
      }
    }

    var changedCount = 0;
    final purgedWorkIds = <String>[];
    if (succeededTids.isNotEmpty) {
      changedCount = await _localFavoriteRepository.markRemovedByTids(
        succeededTids.toSet(),
      );
      final hasAnyActiveThread = await _favoriteLinkService.hasAnyActiveThread(
        normalizedWorkId,
      );
      if (!hasAnyActiveThread) {
        await _workPurgeService.purge(workId: normalizedWorkId, kind: kind);
        purgedWorkIds.add(normalizedWorkId);
      }
    }

    final shouldNotify = changedCount > 0 || purgedWorkIds.isNotEmpty;
    if (shouldNotify) {
      _shelfRefreshBus.notify(
        modules: _modulesForKind(
          kind,
          triggeredPurge: purgedWorkIds.isNotEmpty,
        ),
        reason: failedTids.isEmpty
            ? 'work_unfavorite_completed'
            : 'work_unfavorite_partially_completed',
        source: LibraryMutationSource.threadFavoriteAction,
        workId: normalizedWorkId,
        payload: <String, Object?>{
          'requestedTidCount': requestedTids.length,
          'succeededTidCount': succeededTids.length,
          'failedTidCount': failedTids.length,
          'triggeredPurge': purgedWorkIds.isNotEmpty,
          'kind': kind.name,
        },
      );
    }

    return UnfavoriteResult(
      requestedTids: requestedTids,
      succeededTids: succeededTids,
      failedTids: failedTids,
      purgedWorkIds: purgedWorkIds,
    );
  }

  @override
  Future<UnfavoriteResult> callMany({
    required Map<String, ThreadContentKind> workKinds,
  }) async {
    final requestedTids = <String>[];
    final succeededTids = <String>[];
    final failedTids = <String>[];
    final purgedWorkIds = <String>[];

    for (final entry in workKinds.entries) {
      final result = await call(workId: entry.key, kind: entry.value);
      requestedTids.addAll(result.requestedTids);
      succeededTids.addAll(result.succeededTids);
      failedTids.addAll(result.failedTids);
      purgedWorkIds.addAll(result.purgedWorkIds);
    }

    return UnfavoriteResult(
      requestedTids: requestedTids,
      succeededTids: succeededTids,
      failedTids: failedTids,
      purgedWorkIds: purgedWorkIds,
    );
  }
}

class DefaultUnfavoriteThreadUseCase implements UnfavoriteThreadUseCase {
  const DefaultUnfavoriteThreadUseCase({
    required FavoriteThreadCommand favoriteThreadCommand,
    required FavoriteLinkService favoriteLinkService,
    required LocalFavoriteRepository localFavoriteRepository,
    required WorkPurgeService workPurgeService,
    required LibraryShelfRefreshBus shelfRefreshBus,
  }) : _favoriteThreadCommand = favoriteThreadCommand,
       _favoriteLinkService = favoriteLinkService,
       _localFavoriteRepository = localFavoriteRepository,
       _workPurgeService = workPurgeService,
       _shelfRefreshBus = shelfRefreshBus;

  final FavoriteThreadCommand _favoriteThreadCommand;
  final FavoriteLinkService _favoriteLinkService;
  final LocalFavoriteRepository _localFavoriteRepository;
  final WorkPurgeService _workPurgeService;
  final LibraryShelfRefreshBus _shelfRefreshBus;

  @override
  Future<UnfavoriteResult> call(String tid) async {
    final normalizedTid = tid.trim();
    if (normalizedTid.isEmpty) {
      throw ArgumentError('tid must not be empty');
    }

    final workId = await _favoriteLinkService.workIdForThread(normalizedTid);
    FavoriteWorkLinks? links;
    if (workId != null) {
      links = await _favoriteLinkService.linksForWork(workId);
    }

    final result = await _favoriteThreadCommand.execute(
      SetThreadFavoriteRequest(
        tid: normalizedTid,
        targetState: FavoriteTargetState.unfavorited,
      ),
    );
    if (result is! DataCommandApplied<ThreadFavoriteReceipt>) {
      return UnfavoriteResult(
        requestedTids: <String>[normalizedTid],
        succeededTids: const <String>[],
        failedTids: <String>[normalizedTid],
        purgedWorkIds: const <String>[],
      );
    }

    final changedCount = await _localFavoriteRepository.markRemovedByTids(
      <String>{normalizedTid},
    );

    final purgedWorkIds = <String>[];
    if (workId != null) {
      final hasAnyActiveThread = await _favoriteLinkService.hasAnyActiveThread(
        workId,
      );
      final kind = links?.kind ?? ThreadContentKind.unknown;
      if (!hasAnyActiveThread &&
          (kind == ThreadContentKind.comic ||
              kind == ThreadContentKind.novel)) {
        await _workPurgeService.purge(workId: workId, kind: kind);
        purgedWorkIds.add(workId);
      }
    }

    final kind = links?.kind;
    final shouldNotify = changedCount > 0 || purgedWorkIds.isNotEmpty;
    if (shouldNotify) {
      _shelfRefreshBus.notify(
        modules: _modulesForThread(
          kind,
          triggeredPurge: purgedWorkIds.isNotEmpty,
        ),
        reason: 'thread_unfavorite_completed',
        source: LibraryMutationSource.threadFavoriteAction,
        workId: workId,
        tid: normalizedTid,
        payload: <String, Object?>{
          'requestedTidCount': 1,
          'succeededTidCount': 1,
          'failedTidCount': 0,
          'triggeredPurge': purgedWorkIds.isNotEmpty,
          'kind': kind?.name,
        },
      );
    }

    return UnfavoriteResult(
      requestedTids: <String>[normalizedTid],
      succeededTids: <String>[normalizedTid],
      failedTids: const <String>[],
      purgedWorkIds: purgedWorkIds,
    );
  }

  @override
  Future<UnfavoriteResult> callMany(Set<String> tids) async {
    final requestedTids = <String>[];
    final succeededTids = <String>[];
    final failedTids = <String>[];
    final purgedWorkIds = <String>[];

    for (final tid in tids) {
      final result = await call(tid);
      requestedTids.addAll(result.requestedTids);
      succeededTids.addAll(result.succeededTids);
      failedTids.addAll(result.failedTids);
      purgedWorkIds.addAll(result.purgedWorkIds);
    }

    return UnfavoriteResult(
      requestedTids: requestedTids,
      succeededTids: succeededTids,
      failedTids: failedTids,
      purgedWorkIds: purgedWorkIds,
    );
  }
}

Set<LibraryModuleKey> _modulesForKind(
  ThreadContentKind kind, {
  required bool triggeredPurge,
}) {
  if (!triggeredPurge) {
    return const <LibraryModuleKey>{LibraryModuleKey.favorite};
  }
  switch (kind) {
    case ThreadContentKind.comic:
      return const <LibraryModuleKey>{
        LibraryModuleKey.favorite,
        LibraryModuleKey.comic,
      };
    case ThreadContentKind.novel:
      return const <LibraryModuleKey>{
        LibraryModuleKey.favorite,
        LibraryModuleKey.novel,
      };
    case ThreadContentKind.unknown:
    case ThreadContentKind.forum:
      return const <LibraryModuleKey>{LibraryModuleKey.favorite};
  }
}

Set<LibraryModuleKey> _modulesForThread(
  ThreadContentKind? kind, {
  required bool triggeredPurge,
}) {
  return _modulesForKind(
    kind ?? ThreadContentKind.unknown,
    triggeredPurge: triggeredPurge,
  );
}
