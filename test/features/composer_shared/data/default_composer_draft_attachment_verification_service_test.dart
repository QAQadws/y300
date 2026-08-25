import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/data/services/default_composer_draft_attachment_verification_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_attachment_verification_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_unused_image_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 3, 12);
  late _FakeUnusedImageRepository remote;
  late _FakeDraftRepository drafts;
  late _FakeCacheStorage cache;

  setUp(() {
    remote = _FakeUnusedImageRepository();
    drafts = _FakeDraftRepository();
    cache = _FakeCacheStorage();
  });

  DefaultComposerDraftAttachmentVerificationService service() {
    return DefaultComposerDraftAttachmentVerificationService(
      unusedImageRepository: remote,
      draftRepository: drafts,
      cacheStorage: cache,
      bbCodeService: const ComposerAttachBbCodeService(),
      now: () => now,
    );
  }

  test('does not request a catalog for drafts without an aid', () async {
    final result = await service().verify(_draft(message: 'plain text'));

    expect(remote.loadCount, 0);
    expect(
      result.verification.status,
      ComposerDraftAttachmentVerificationStatus.notRequired,
    );
  });

  test(
    'fails closed without mutating metadata when catalog loading fails',
    () async {
      remote.result = const ApiFailure<List<ComposerUnusedImage>>(
        ApiError(type: ApiErrorType.network, message: 'offline'),
      );
      final original = _draft(
        message: '[attach]12[/attach]',
        attachments: [_attachment('12', uploadedAt: now)],
      );

      final result = await service().verify(original);

      expect(result.draft, same(original));
      expect(result.verification.failed, isTrue);
      expect(result.verification.unverifiedAids, <String>{'12'});
      expect(drafts.invalidatedAids, isEmpty);
      expect(drafts.saved, isEmpty);
    },
  );

  test('keeps a valid managed copy and publishes the remote catalog', () async {
    remote.result = ApiSuccess<List<ComposerUnusedImage>>([
      _remote('12'),
      _remote('99'),
    ]);
    cache.existingPaths.add('/cache/12.jpg');
    final original = _draft(
      message: '[attachimg]12[/attachimg]',
      attachments: [
        _attachment('12', uploadedAt: now, cachePath: '/cache/12.jpg'),
      ],
    );

    final result = await service().verify(original);

    expect(result.draft, same(original));
    expect(result.verification.verified, isTrue);
    expect(result.verification.verifiedImagesByAid.keys, <String>['12']);
    expect(cache.retainedSources, isEmpty);
  });

  test('backfills a managed copy from a still-fresh legacy source', () async {
    remote.result = ApiSuccess<List<ComposerUnusedImage>>([_remote('12')]);
    cache.retainedPath = '/cache/retained.jpg';
    final original = _draft(
      message: '[attach]12[/attach]',
      attachments: [
        _attachment('12', uploadedAt: now.subtract(const Duration(days: 13))),
      ],
    );

    final result = await service().verify(original);

    expect(cache.retainedSources, <String>['/gallery/12.jpg']);
    expect(
      result.draft.imageAttachments.single.cachePath,
      '/cache/retained.jpg',
    );
    expect(drafts.saved, isEmpty);
  });

  test('does not rebuild a managed copy after the 14-day boundary', () async {
    remote.result = ApiSuccess<List<ComposerUnusedImage>>([_remote('12')]);
    cache.retainedPath = '/cache/should-not-be-used.jpg';
    final original = _draft(
      message: '[attach]12[/attach]',
      attachments: [
        _attachment(
          '12',
          uploadedAt: now.subtract(const Duration(days: 14)),
          cachePath: '/cache/missing.jpg',
        ),
      ],
    );

    final result = await service().verify(original);

    expect(cache.retainedSources, isEmpty);
    expect(cache.deletedPaths, <String>['/cache/missing.jpg']);
    expect(result.draft.imageAttachments.single.aid, '12');
    expect(result.draft.imageAttachments.single.cachePath, isNull);
    expect(result.verification.verifiedImagesByAid['12'], isNotNull);
  });

  test(
    'invalid aid removes metadata and managed copy but preserves BBCode',
    () async {
      remote.result = ApiSuccess<List<ComposerUnusedImage>>([_remote('22')]);
      final original = _draft(
        message: 'A\n[attach]11[/attach]\n[attach]22[/attach]',
        attachments: [
          _attachment('11', uploadedAt: now, cachePath: '/cache/11.jpg'),
          _attachment('22', uploadedAt: now, cachePath: '/cache/22.jpg'),
        ],
      );

      final result = await service().verify(original);

      expect(drafts.invalidatedAids, <String>{'11'});
      expect(result.draft.message, original.message);
      expect(result.draft.imageAttachments.single.aid, '22');
      expect(result.verification.invalidAidCount, 1);
    },
  );
}

ComposerDraftSnapshot _draft({
  required String message,
  List<ComposerImageAttachment> attachments = const <ComposerImageAttachment>[],
}) {
  return ComposerDraftSnapshot(
    identity: const ComposerDraftIdentity.newThread(fid: '5'),
    message: message,
    useSignature: true,
    updatedAt: DateTime.utc(2026, 8, 3),
    imageAttachments: attachments,
  );
}

ComposerImageAttachment _attachment(
  String aid, {
  required DateTime uploadedAt,
  String? cachePath,
}) {
  return ComposerImageAttachment(
    localId: 'local-$aid',
    localPath: '/gallery/$aid.jpg',
    fileName: '$aid.jpg',
    mimeType: 'image/jpeg',
    order: int.parse(aid),
    status: ComposerImageAttachmentStatus.uploaded,
    aid: aid,
    uploadedAt: uploadedAt,
    cachePath: cachePath,
  );
}

ComposerUnusedImage _remote(String aid) {
  return ComposerUnusedImage(
    aid: aid,
    thumbnailUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=image&aid=$aid&size=300x300',
    ),
    thumbnailRefererUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=ajax&action=imagelist&posttime=0',
    ),
    fileName: '$aid.jpg',
  );
}

final class _FakeUnusedImageRepository
    implements ComposerUnusedImageRepository {
  ApiResult<List<ComposerUnusedImage>> result =
      const ApiSuccess<List<ComposerUnusedImage>>(<ComposerUnusedImage>[]);
  var loadCount = 0;

  @override
  Future<ApiResult<List<ComposerUnusedImage>>> loadUnusedImages() async {
    loadCount += 1;
    return result;
  }

  @override
  Future<ApiResult<ComposerUnusedImageDeleteResult>> deleteUnusedImage(
    String aid,
  ) {
    throw UnimplementedError();
  }
}

final class _FakeDraftRepository
    implements ComposerDraftRepository, ComposerDraftAttachmentInvalidator {
  final List<ComposerDraftSnapshot> saved = <ComposerDraftSnapshot>[];
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
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    saved.add(draft);
  }

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {}

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    return null;
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    return const <ComposerDraftSnapshot>[];
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    return const ComposerDraftPruneResult(removedCount: 0, keptCount: 0);
  }
}

final class _FakeCacheStorage
    implements ComposerUploadCacheStorage, ComposerUploadCacheRetentionStorage {
  final Set<String> existingPaths = <String>{};
  final List<String> retainedSources = <String>[];
  final List<String> deletedPaths = <String>[];
  String? retainedPath;

  @override
  bool cachePathExists(String? cachePath) {
    return cachePath != null && existingPaths.contains(cachePath);
  }

  @override
  Future<bool> deleteCachePathIfOwned(String? cachePath) async {
    if (cachePath == null) {
      return false;
    }
    deletedPaths.add(cachePath);
    return true;
  }

  @override
  Future<String?> retainUploadedCopy({
    required String sourcePath,
    required String localId,
    required String fileName,
  }) async {
    retainedSources.add(sourcePath);
    return retainedPath;
  }
}
