import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_unused_image_repository.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_unused_image_management_page.dart';
import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('shows cache hits immediately and serializes network misses', (
    tester,
  ) async {
    final repository = _FakeUnusedImageRepository(
      images: [_image('1'), _image('2'), _image('3')],
    );
    final cache = _FakeImageCacheService(
      cachedByAid: const <String, String>{'1': '/cache/1.jpg'},
      now: tester.binding.clock.now,
    );
    await tester.pumpWidget(_testApp(repository: repository, cache: cache));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byKey(const Key('unused-image-card-1')), findsOneWidget);
    expect(find.byKey(const Key('unused-image-thumbnail-1')), findsOneWidget);
    final thumbnail = tester.widget<Image>(
      find.byKey(const Key('unused-image-thumbnail-1')),
    );
    expect(thumbnail.fit, BoxFit.contain);
    final grid = tester.widget<GridView>(
      find.byKey(const Key('unused-images-grid')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent)
          .maxCrossAxisExtent,
      300,
    );
    expect(cache.ensureAids, <String>['2']);

    await tester.pump(const Duration(milliseconds: 598));
    expect(cache.ensureAids, <String>['2']);
    await tester.pump(const Duration(milliseconds: 2));
    expect(cache.ensureAids, <String>['2', '3']);
    expect(
      cache.ensureStartedAt[1].difference(cache.ensureStartedAt[0]),
      greaterThanOrEqualTo(const Duration(milliseconds: 600)),
    );
  });

  testWidgets('stops queued network misses after the page is disposed', (
    tester,
  ) async {
    final repository = _FakeUnusedImageRepository(
      images: [_image('1'), _image('2'), _image('3')],
    );
    final cache = _FakeImageCacheService(now: tester.binding.clock.now);
    await tester.pumpWidget(_testApp(repository: repository, cache: cache));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(cache.ensureAids, <String>['1']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    expect(cache.ensureAids, <String>['1']);
  });

  testWidgets('confirms deletion and reconciles drafts and thumbnail cache', (
    tester,
  ) async {
    final repository = _FakeUnusedImageRepository(images: [_image('12')]);
    final drafts = _FakeDraftRepository();
    final cache = _FakeImageCacheService(
      cachedByAid: const <String, String>{'12': '/cache/12.jpg'},
      now: tester.binding.clock.now,
    );
    await tester.pumpWidget(
      _testApp(repository: repository, cache: cache, drafts: drafts),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('unused-image-delete-12')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('unused-images-confirm-delete')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('unused-images-confirm-delete')));
    await tester.pump();
    await tester.pump();

    expect(repository.deletedAids, <String>['12']);
    expect(drafts.invalidatedAids, <String>{'12'});
    expect(cache.deletedOwnerAids, <String>['12']);
    expect(find.byKey(const Key('unused-image-card-12')), findsNothing);
  });

  testWidgets('keeps a card when server deletion is not confirmed', (
    tester,
  ) async {
    final repository = _FakeUnusedImageRepository(
      images: [_image('12')],
      deleteSucceeds: false,
    );
    final cache = _FakeImageCacheService(
      cachedByAid: const <String, String>{'12': '/cache/12.jpg'},
      now: tester.binding.clock.now,
    );
    await tester.pumpWidget(_testApp(repository: repository, cache: cache));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('unused-image-delete-12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unused-images-confirm-delete')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('unused-image-card-12')), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('renders localized empty and retryable error states', (
    tester,
  ) async {
    final repository = _FakeUnusedImageRepository(images: const []);
    final cache = _FakeImageCacheService(now: tester.binding.clock.now);
    await tester.pumpWidget(_testApp(repository: repository, cache: cache));
    await tester.pump();
    expect(find.byKey(const Key('unused-images-empty-scroll')), findsOneWidget);

    repository.loadFails = true;
    await tester.drag(
      find.byKey(const Key('unused-images-empty-scroll')),
      const Offset(0, 300),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('unused-images-retry')), findsOneWidget);

    repository.loadFails = false;
    await tester.tap(find.byKey(const Key('unused-images-retry')));
    await tester.pump();
    expect(find.byKey(const Key('unused-images-empty-scroll')), findsOneWidget);
  });
}

Widget _testApp({
  required _FakeUnusedImageRepository repository,
  required _FakeImageCacheService cache,
  _FakeDraftRepository? drafts,
}) {
  return ProviderScope(
    overrides: [
      composerUnusedImageRepositoryProvider.overrideWithValue(repository),
      imageCacheServiceProvider.overrideWithValue(cache),
      composerDraftRepositoryProvider.overrideWithValue(
        drafts ?? _FakeDraftRepository(),
      ),
    ],
    child: const LocalizedTestApp(home: ComposerUnusedImageManagementPage()),
  );
}

ComposerUnusedImage _image(String aid) {
  return ComposerUnusedImage(
    aid: aid,
    thumbnailUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=image&aid=$aid&size=300x300',
    ),
    fileName: '$aid.jpg',
  );
}

final class _FakeUnusedImageRepository
    implements ComposerUnusedImageRepository {
  _FakeUnusedImageRepository({
    required this.images,
    this.deleteSucceeds = true,
  });

  final List<ComposerUnusedImage> images;
  final bool deleteSucceeds;
  bool loadFails = false;
  final List<String> deletedAids = <String>[];

  @override
  Future<ApiResult<List<ComposerUnusedImage>>> loadUnusedImages() async {
    if (loadFails) {
      return const ApiFailure<List<ComposerUnusedImage>>(
        ApiError(type: ApiErrorType.network, message: 'offline'),
      );
    }
    return ApiSuccess<List<ComposerUnusedImage>>(images);
  }

  @override
  Future<ApiResult<ComposerUnusedImageDeleteResult>> deleteUnusedImage(
    String aid,
  ) async {
    deletedAids.add(aid);
    return ApiSuccess(
      ComposerUnusedImageDeleteResult(
        aid: aid,
        outcome: deleteSucceeds
            ? ComposerUnusedImageDeleteOutcome.deleted
            : ComposerUnusedImageDeleteOutcome.notDeleted,
        deletedCount: deleteSucceeds ? 1 : 0,
      ),
    );
  }
}

final class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({
    this.cachedByAid = const <String, String>{},
    required DateTime Function() now,
  }) : _now = now;

  final Map<String, String> cachedByAid;
  final DateTime Function() _now;
  final List<String> ensureAids = <String>[];
  final List<DateTime> ensureStartedAt = <DateTime>[];
  final List<String> deletedOwnerAids = <String>[];

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    final aid = cacheKey.split('/').last;
    final path = cachedByAid[aid];
    if (path == null) {
      return null;
    }
    return CachedImageResult(
      success: true,
      cacheKey: cacheKey,
      localPath: path,
      fromCache: true,
    );
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    ensureAids.add(request.ownerId);
    ensureStartedAt.add(_now());
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: '/cache/${request.ownerId}.jpg',
    );
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    deletedOwnerAids.add(ownerId);
    return 1;
  }

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async => 0;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async => CachedImageResult.failed;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}

final class _FakeDraftRepository
    implements ComposerDraftRepository, ComposerDraftAttachmentInvalidator {
  Set<String> invalidatedAids = <String>{};

  @override
  Future<ComposerDraftAttachmentInvalidationResult> invalidateAttachmentAids({
    required Set<String> aids,
    ComposerDraftIdentity? identity,
  }) async {
    invalidatedAids = Set<String>.of(aids);
    return const ComposerDraftAttachmentInvalidationResult();
  }

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {}

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async => const <ComposerDraftSnapshot>[];

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async => null;

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async => const ComposerDraftPruneResult(removedCount: 0, keptCount: 0);

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {}
}
