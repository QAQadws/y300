import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

class LibraryCoverImageSpecRequest {
  const LibraryCoverImageSpecRequest({
    required this.workId,
    required this.imageSpec,
    required this.useCustomCover,
  });

  final String workId;
  final ForumImageLoadSpec imageSpec;
  final bool useCustomCover;
}

class LibraryCoverImageAdapter {
  const LibraryCoverImageAdapter();

  LibraryCoverImageSpecRequest? buildCoverSpec({
    required LibraryModuleKey moduleKey,
    required LibraryWorkItem item,
    ImageCacheOwnerType? ownerType,
    String? ownerId,
  }) {
    final normalizedOwnerId = _nonEmpty(ownerId);
    if (moduleKey == LibraryModuleKey.favorite &&
        (ownerType == null || normalizedOwnerId == null)) {
      return null;
    }
    final resolvedOwnerType = ownerType ?? _ownerTypeFor(moduleKey);
    final resolvedOwnerId = normalizedOwnerId ?? item.workId;
    final customSource = _nonEmpty(item.customCoverImageUrl);
    if (customSource != null) {
      if (_nonEmpty(item.customCoverLocalPath) != null) {
        return null;
      }
      return LibraryCoverImageSpecRequest(
        workId: item.workId,
        useCustomCover: true,
        imageSpec: ForumImageLoadSpec(
          kind: ForumImageKind.customCover,
          url: Uri.parse(customSource),
          ownerType: resolvedOwnerType,
          ownerId: resolvedOwnerId,
          cacheKey: ImageCacheKeys.customCover(
            ownerType: resolvedOwnerType.dbValue,
            ownerId: resolvedOwnerId,
          ),
          protected: true,
          allowReaderOpen: false,
        ),
      );
    }

    if (_nonEmpty(item.customCoverLocalPath) != null ||
        _nonEmpty(item.coverLocalPath) != null) {
      return null;
    }
    final coverSource = _nonEmpty(item.coverImageUrl);
    if (coverSource == null) {
      return null;
    }
    return LibraryCoverImageSpecRequest(
      workId: item.workId,
      useCustomCover: false,
      imageSpec: ForumImageLoadSpec(
        kind: moduleKey == LibraryModuleKey.favorite
            ? ForumImageKind.favoriteCover
            : ForumImageKind.cover,
        url: Uri.parse(coverSource),
        ownerType: resolvedOwnerType,
        ownerId: resolvedOwnerId,
        cacheKey: _coverCacheKey(
          moduleKey: moduleKey,
          ownerType: resolvedOwnerType,
          ownerId: resolvedOwnerId,
        ),
        allowReaderOpen: false,
      ),
    );
  }

  LibraryCoverImageSpecRequest? buildDetailCoverSpec({
    required LibraryModuleKey moduleKey,
    required LibraryDetailHeader header,
    ImageCacheOwnerType? ownerType,
    String? ownerId,
  }) {
    return buildCoverSpec(
      moduleKey: moduleKey,
      item: LibraryWorkItem(
        workId: header.workId,
        categoryId: 'detail',
        title: header.title,
        coverImageUrl: header.coverImageUrl,
        customCoverImageUrl: header.customCoverImageUrl,
        coverLocalPath: header.coverLocalPath,
        customCoverLocalPath: header.customCoverLocalPath,
        customCoverFocusX: header.customCoverFocusX,
        customCoverFocusY: header.customCoverFocusY,
        unreadCount: 0,
        totalChapterCount: 0,
        readChapterCount: 0,
        addedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      ownerType: ownerType,
      ownerId: ownerId,
    );
  }

  ImageCacheOwnerType _ownerTypeFor(LibraryModuleKey moduleKey) {
    return switch (moduleKey) {
      LibraryModuleKey.comic => ImageCacheOwnerType.comic,
      LibraryModuleKey.novel => ImageCacheOwnerType.novel,
      LibraryModuleKey.favorite => ImageCacheOwnerType.favorite,
    };
  }

  String _coverCacheKey({
    required LibraryModuleKey moduleKey,
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) {
    return switch (ownerType) {
      ImageCacheOwnerType.comic => ImageCacheKeys.comicCover(ownerId),
      ImageCacheOwnerType.novel => ImageCacheKeys.novelCover(ownerId),
      _ => switch (moduleKey) {
        LibraryModuleKey.comic => ImageCacheKeys.comicCover(ownerId),
        LibraryModuleKey.novel => ImageCacheKeys.novelCover(ownerId),
        LibraryModuleKey.favorite => ImageCacheKeys.comicCover(ownerId),
      },
    };
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
