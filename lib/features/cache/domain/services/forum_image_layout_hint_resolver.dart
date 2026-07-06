import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';

class ForumImageLayoutHintResolver {
  const ForumImageLayoutHintResolver({this.fallbackBlockAspectRatio = 0.7});

  final double fallbackBlockAspectRatio;

  ForumImageLayoutHint resolve({
    required ForumImageLoadSpec spec,
    ForumImageDimensions? cacheDimensions,
  }) {
    final htmlDimensions = ForumImageDimensions.fromHtmlSpec(spec);
    switch (spec.kind) {
      case ForumImageKind.threadInline:
      case ForumImageKind.threadAttachment:
      case ForumImageKind.blogInline:
      case ForumImageKind.externalInline:
        return _resolveBlockImage(
          htmlDimensions: htmlDimensions,
          cacheDimensions: cacheDimensions,
        );
      case ForumImageKind.remoteSmiley:
        return _resolveIntrinsicImage(
          htmlDimensions: htmlDimensions,
          cacheDimensions: cacheDimensions,
        );
      case ForumImageKind.avatar:
        return const ForumImageLayoutHint(
          layoutMode: ForumImageLayoutMode.fixedAvatar,
          dimensionSource: ForumImageDimensionSource.fixedContainer,
        );
      case ForumImageKind.forumHeadImage:
        return const ForumImageLayoutHint(
          layoutMode: ForumImageLayoutMode.fixedBanner,
          dimensionSource: ForumImageDimensionSource.fixedContainer,
        );
      case ForumImageKind.forumIcon:
        return const ForumImageLayoutHint(
          layoutMode: ForumImageLayoutMode.fixedIcon,
          dimensionSource: ForumImageDimensionSource.fixedContainer,
        );
      case ForumImageKind.cover:
      case ForumImageKind.customCover:
      case ForumImageKind.favoriteCover:
        return const ForumImageLayoutHint(
          layoutMode: ForumImageLayoutMode.fixedCover,
          dimensionSource: ForumImageDimensionSource.fixedContainer,
        );
      case ForumImageKind.comicReaderPage:
        return const ForumImageLayoutHint(
          layoutMode: ForumImageLayoutMode.readerPage,
          dimensionSource: ForumImageDimensionSource.fixedContainer,
        );
    }
  }

  ForumImageLayoutHint _resolveBlockImage({
    required ForumImageDimensions? htmlDimensions,
    required ForumImageDimensions? cacheDimensions,
  }) {
    final known = _valid(htmlDimensions) ?? _valid(cacheDimensions);
    if (known != null) {
      return ForumImageLayoutHint(
        layoutMode: ForumImageLayoutMode.blockWithKnownAspectRatio,
        dimensionSource: known.source,
        aspectRatio: known.aspectRatio,
      );
    }
    return ForumImageLayoutHint(
      layoutMode: ForumImageLayoutMode.blockWithFallbackAspectRatio,
      aspectRatio: fallbackBlockAspectRatio,
    );
  }

  ForumImageLayoutHint _resolveIntrinsicImage({
    required ForumImageDimensions? htmlDimensions,
    required ForumImageDimensions? cacheDimensions,
  }) {
    final known = _valid(htmlDimensions) ?? _valid(cacheDimensions);
    return ForumImageLayoutHint(
      layoutMode: ForumImageLayoutMode.inlineIntrinsic,
      dimensionSource: known?.source,
      displaySize: known?.size,
      aspectRatio: known?.aspectRatio,
    );
  }

  ForumImageDimensions? _valid(ForumImageDimensions? dimensions) {
    if (dimensions == null || !dimensions.isValid) {
      return null;
    }
    return dimensions;
  }
}
