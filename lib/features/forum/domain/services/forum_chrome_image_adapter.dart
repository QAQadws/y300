import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

class ForumChromeImageAdapter {
  const ForumChromeImageAdapter();

  ForumImageLoadSpec? carouselImage(String imageUrl) {
    final uri = _parseImageUri(imageUrl);
    if (uri == null) {
      return null;
    }
    return ForumImageLoadSpec(
      kind: ForumImageKind.forumHeadImage,
      url: uri,
      ownerId: 'home',
      ownerType: ImageCacheOwnerType.forum,
      allowReaderOpen: false,
    );
  }

  ForumImageLoadSpec? headImage({
    required String fid,
    required String imageUrl,
  }) {
    final uri = _parseImageUri(imageUrl);
    if (uri == null) {
      return null;
    }
    final owner = fid.trim();
    return ForumImageLoadSpec(
      kind: ForumImageKind.forumHeadImage,
      url: uri,
      ownerId: owner.isEmpty ? 'forum-head' : 'forum:$owner',
      ownerType: ImageCacheOwnerType.forum,
      allowReaderOpen: false,
    );
  }

  ForumImageLoadSpec? forumIcon({
    required String fid,
    required String imageUrl,
  }) {
    final uri = _parseImageUri(imageUrl);
    if (uri == null) {
      return null;
    }
    final owner = fid.trim();
    return ForumImageLoadSpec(
      kind: ForumImageKind.forumIcon,
      url: uri,
      ownerId: owner.isEmpty ? 'forum-icon' : owner,
      ownerType: ImageCacheOwnerType.forumDisplay,
      allowReaderOpen: false,
    );
  }

  Uri? _parseImageUri(String imageUrl) {
    final value = imageUrl.trim();
    if (value.isEmpty) {
      return null;
    }
    return Uri.tryParse(value);
  }
}
