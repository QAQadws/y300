import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/composer_shared/data/providers/composer_draft_providers.dart';
import 'package:y300/features/composer_shared/data/repositories/package_composer_unused_image_repository.dart';
import 'package:y300/features/composer_shared/data/services/default_composer_draft_attachment_verification_service.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/repositories/package_composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/data/repositories/sticker_catalog_repository.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_tokenizer.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';
import 'package:y300/features/composer_shared/domain/services/composer_submission_failure_classifier.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_verification_service.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_bbcode_tokenizer.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_unused_image_repository.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';

export 'package:y300/features/composer_shared/data/providers/composer_preferences_providers.dart';
export 'package:y300/features/composer_shared/data/providers/composer_draft_providers.dart';

/// composer_shared 模块的 Riverpod 接线集合。
///
/// 这里的 provider 在 reply 与（后续阶段的）posting 之间共享。具体的回复/发帖
/// 业务 provider（回复 command、`replyComposerControllerProvider` 等）
/// 仍然留在各自的 feature 目录里，它们消费这里暴露的依赖。

final stickerCatalogRepositoryProvider = Provider<StickerCatalogRepository>((
  ref,
) {
  return PackageStickerCatalogRepository(
    repository: ref.watch(yamiboForumClientProvider).stickerCatalog!,
  );
});

final stickerGroupsProvider = FutureProvider<List<StickerGroup>>((ref) {
  return ref.read(stickerCatalogRepositoryProvider).loadStickerGroups();
});

final composerStickerImageCacheLoaderProvider =
    Provider<ComposerStickerImageCacheLoader>((ref) {
      return ComposerStickerImageCacheLoader(
        imageCacheService: ref.watch(imageCacheServiceProvider),
      );
    });

final stickerBbCodeTokenizerProvider = Provider<StickerBbCodeTokenizer>((_) {
  return const StickerBbCodeTokenizer();
});

final composerAttachBbCodeTokenizerProvider =
    Provider<ComposerAttachBbCodeTokenizer>((_) {
      return const ComposerAttachBbCodeTokenizer();
    });

final composerSubmissionFailureClassifierProvider =
    Provider<ComposerSubmissionFailureClassifier>((_) {
      return const ComposerSubmissionFailureClassifier();
    });

final composerImagePickerProvider = Provider<ComposerImagePicker>((_) {
  return ImagePickerComposerImagePicker();
});

final composerAttachmentRepositoryProvider =
    Provider<ComposerAttachmentRepository>((ref) {
      final client = ref.read(yamiboForumClientProvider);
      return PackageComposerAttachmentRepository(
        preparation: client.imageAttachmentUploadPreparation!,
        command: client.imageAttachmentUploadCommand!,
        cacheStorage: ref.read(composerUploadCacheStorageProvider),
      );
    });

final composerUnusedImageRepositoryProvider =
    Provider<ComposerUnusedImageRepository>((ref) {
      final client = ref.watch(yamiboForumClientProvider);
      return PackageComposerUnusedImageRepository(
        directory: client.unusedImageAttachments!,
        deleteCommand: client.unusedImageAttachmentDelete!,
      );
    });

final composerDraftAttachmentVerificationServiceProvider =
    Provider<ComposerDraftAttachmentVerificationService>((ref) {
      return DefaultComposerDraftAttachmentVerificationService(
        unusedImageRepository: ref.watch(composerUnusedImageRepositoryProvider),
        draftRepository: ref.watch(composerDraftRepositoryProvider),
        cacheStorage: ref.watch(composerUploadCacheStorageProvider),
        bbCodeService: ref.watch(composerAttachBbCodeServiceProvider),
      );
    });

final composerAttachBbCodeServiceProvider =
    Provider<ComposerAttachBbCodeService>((_) {
      return const ComposerAttachBbCodeService();
    });

final composerImageUploadCoordinatorProvider =
    Provider<ComposerImageUploadCoordinator>((ref) {
      return SerialComposerImageUploadCoordinator(
        repository: ref.read(composerAttachmentRepositoryProvider),
      );
    });

final forumBbCodeRendererProvider = Provider<ForumBbCodeRenderer>((ref) {
  return FlutterBbCodeForumRenderer(
    stickerTokenizer: ref.read(stickerBbCodeTokenizerProvider),
    attachTokenizer: ref.read(composerAttachBbCodeTokenizerProvider),
  );
});
