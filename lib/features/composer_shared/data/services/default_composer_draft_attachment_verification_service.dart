import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_attachment_verification_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_unused_image_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_verification_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_attachment_expiry_policy.dart';

final class DefaultComposerDraftAttachmentVerificationService
    implements ComposerDraftAttachmentVerificationService {
  const DefaultComposerDraftAttachmentVerificationService({
    required ComposerUnusedImageRepository unusedImageRepository,
    required ComposerDraftRepository draftRepository,
    required ComposerUploadCacheStorage cacheStorage,
    required ComposerAttachBbCodeService bbCodeService,
    this.cacheExpiryPolicy = const ComposerImageAttachmentExpiryPolicy(),
    DateTime Function()? now,
  }) : _unusedImageRepository = unusedImageRepository,
       _draftRepository = draftRepository,
       _cacheStorage = cacheStorage,
       _bbCodeService = bbCodeService,
       _now = now ?? DateTime.now;

  final ComposerUnusedImageRepository _unusedImageRepository;
  final ComposerDraftRepository _draftRepository;
  final ComposerUploadCacheStorage _cacheStorage;
  final ComposerAttachBbCodeService _bbCodeService;
  final ComposerImageAttachmentExpiryPolicy cacheExpiryPolicy;
  final DateTime Function() _now;

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) async {
    final referencedAids = <String>{
      ..._bbCodeService.extractAttachAids(draft.message),
      for (final attachment in draft.imageAttachments)
        if (attachment.aid?.trim() case final String aid when aid.isNotEmpty)
          aid,
    };
    if (referencedAids.isEmpty) {
      return ComposerDraftAttachmentVerificationResult(
        draft: draft,
        verification: const ComposerDraftAttachmentVerification.notRequired(),
      );
    }

    final remoteResult = await _unusedImageRepository.loadUnusedImages();
    if (remoteResult case ApiFailure<List<ComposerUnusedImage>>(:final error)) {
      return ComposerDraftAttachmentVerificationResult(
        draft: draft,
        verification: ComposerDraftAttachmentVerification.failed(
          unverifiedAids: referencedAids,
          failureDetail: error.message.trim().isEmpty ? null : error.message,
        ),
      );
    }

    final images = remoteResult.dataOrNull!;
    final catalogByAid = <String, ComposerUnusedImage>{
      for (final image in images) image.aid: image,
    };
    final imagesByAid = <String, ComposerUnusedImage>{
      for (final aid in referencedAids) aid: ?catalogByAid[aid],
    };
    final invalidAids = referencedAids.difference(imagesByAid.keys.toSet());
    if (invalidAids.isNotEmpty) {
      await _draftRepository.invalidateAttachmentAids(
        aids: invalidAids,
        identity: draft.identity,
      );
    }
    var reconciled = _withoutInvalidAttachmentMetadata(draft, invalidAids);
    reconciled = await _backfillOwnedCacheCopies(
      reconciled,
      validAids: imagesByAid.keys.toSet(),
    );
    return ComposerDraftAttachmentVerificationResult(
      draft: reconciled,
      verification: ComposerDraftAttachmentVerification.verified(
        imagesByAid: imagesByAid,
        checkedAids: referencedAids,
        invalidAidCount: invalidAids.length,
      ),
    );
  }

  ComposerDraftSnapshot _withoutInvalidAttachmentMetadata(
    ComposerDraftSnapshot draft,
    Set<String> invalidAids,
  ) {
    if (invalidAids.isEmpty) {
      return draft;
    }
    return _copyDraft(
      draft,
      imageAttachments: [
        for (final attachment in draft.imageAttachments)
          if (!invalidAids.contains(attachment.aid?.trim())) attachment,
      ],
    );
  }

  Future<ComposerDraftSnapshot> _backfillOwnedCacheCopies(
    ComposerDraftSnapshot draft, {
    required Set<String> validAids,
  }) async {
    var changed = false;
    final nextAttachments = <ComposerImageAttachment>[];
    for (final attachment in draft.imageAttachments) {
      final aid = attachment.aid?.trim();
      if (aid == null || !validAids.contains(aid)) {
        nextAttachments.add(attachment);
        continue;
      }
      final cachePath = attachment.cachePath?.trim();
      if (cachePath != null &&
          cachePath.isNotEmpty &&
          _cacheStorage.cachePathExists(cachePath)) {
        nextAttachments.add(attachment);
        continue;
      }
      if (cacheExpiryPolicy.isExpired(
        uploadedAt: attachment.uploadedAt,
        now: _now(),
      )) {
        if (cachePath != null && cachePath.isNotEmpty) {
          await _cacheStorage.deleteCachePathIfOwned(cachePath);
          nextAttachments.add(attachment.copyWith(cachePath: null));
          changed = true;
        } else {
          nextAttachments.add(attachment);
        }
        continue;
      }
      String? retainedPath;
      try {
        retainedPath = await _cacheStorage.retainUploadedCopy(
          sourcePath: attachment.localPath,
          localId: attachment.localId,
          fileName: attachment.fileName,
        );
      } catch (_) {
        retainedPath = null;
      }
      if (retainedPath == null || retainedPath.trim().isEmpty) {
        if (cachePath != null && cachePath.isNotEmpty) {
          nextAttachments.add(attachment.copyWith(cachePath: null));
          changed = true;
        } else {
          nextAttachments.add(attachment);
        }
        continue;
      }
      nextAttachments.add(attachment.copyWith(cachePath: retainedPath));
      changed = true;
    }
    if (!changed) {
      return draft;
    }
    return _copyDraft(draft, imageAttachments: nextAttachments);
  }

  ComposerDraftSnapshot _copyDraft(
    ComposerDraftSnapshot source, {
    required List<ComposerImageAttachment> imageAttachments,
  }) {
    return ComposerDraftSnapshot(
      identity: source.identity,
      message: source.message,
      subject: source.subject,
      extras: source.extras,
      useSignature: source.useSignature,
      updatedAt: source.updatedAt,
      imageAttachments: imageAttachments,
    );
  }
}
