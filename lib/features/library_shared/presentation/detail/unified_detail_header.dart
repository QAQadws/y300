import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:y300/core/media/cover_focal_point.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_palette.dart';

bool hasUnifiedDetailCover(LibraryDetailHeader header) {
  return <String?>[
    header.customCoverLocalPath,
    header.coverLocalPath,
    header.customCoverImageUrl,
    header.coverImageUrl,
  ].any((value) => value?.trim().isNotEmpty == true);
}

/// 顶部视觉区与动作区作为一个滚动单元，避免 RefreshIndicator 下拉拉伸时
/// 两个 Sliver 独立变形造成肉眼可见的缝隙。
class UnifiedDetailHeaderSection extends StatelessWidget {
  const UnifiedDetailHeaderSection({
    super.key,
    required this.header,
    required this.moduleKey,
    required this.topInset,
    required this.palette,
    required this.imageHeaderBuilder,
    required this.onToggleShelf,
    required this.onRefresh,
    required this.onOpenThread,
  });

  static const double _seamBridgeHeight = 6;

  final LibraryDetailHeader header;
  final LibraryModuleKey moduleKey;
  final double topInset;
  final UnifiedDetailPalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final VoidCallback onToggleShelf;
  final VoidCallback onRefresh;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    if (!hasUnifiedDetailCover(header)) {
      return Column(
        key: const Key('unified-detail-header-section'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlainHeroInfoSection(
            header: header,
            moduleKey: moduleKey,
            topInset: topInset,
            palette: palette,
          ),
          _HeaderActionsRow(
            header: header,
            onToggleShelf: onToggleShelf,
            onRefresh: onRefresh,
            onOpenThread: onOpenThread,
          ),
        ],
      );
    }
    return Stack(
      key: const Key('unified-detail-header-section'),
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeroInfoSection(
              header: header,
              moduleKey: moduleKey,
              topInset: topInset,
              palette: palette,
              imageHeaderBuilder: imageHeaderBuilder,
            ),
            _HeaderActionsRow(
              header: header,
              onToggleShelf: onToggleShelf,
              onRefresh: onRefresh,
              onOpenThread: onOpenThread,
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          top: _HeroInfoSection.heightFor(topInset) - _seamBridgeHeight / 2,
          height: _seamBridgeHeight,
          child: IgnorePointer(
            child: ColoredBox(
              key: const Key('unified-detail-header-seam-bridge'),
              color: palette.headerGradientEnd,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 可随列表滚动消失的封面+元信息区。
class _HeroInfoSection extends StatelessWidget {
  const _HeroInfoSection({
    required this.header,
    required this.moduleKey,
    required this.topInset,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  // Hero 区高度（含状态栏与 AppBar 覆盖区）
  // 需要容纳：封面(168) + 元信息区 + 操作区，过小会导致底部溢出。
  static const double _heroExtraHeight = 240;
  // 封面与文字块的内边距
  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(30, 0, 12, 30);

  static double heightFor(double topInset) =>
      topInset + kToolbarHeight + _heroExtraHeight;

  final LibraryDetailHeader header;
  final LibraryModuleKey moduleKey;
  final double topInset;
  final UnifiedDetailPalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    final title = header.title;
    final author = _nonEmpty(header.author);
    final group = _nonEmpty(header.translationGroup);

    return SizedBox(
      key: const Key('unified-detail-cover-header'),
      height: heightFor(topInset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DetailHeaderBackground(
            coverImageUrl: header.coverImageUrl,
            customCoverImageUrl: header.customCoverImageUrl,
            coverLocalPath: header.coverLocalPath,
            customCoverLocalPath: header.customCoverLocalPath,
            palette: palette,
            imageHeaderBuilder: imageHeaderBuilder,
          ),
          Padding(
            padding: _contentPadding.copyWith(
              top: topInset + kToolbarHeight + 4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _CoverImage(
                  url: _preferredRemoteUrl(header),
                  localPath: _preferredLocalPath(header),
                  alignment: _isShowingCustomCover(header)
                      ? coverAlignmentFromFocus(
                          header.customCoverFocusX,
                          header.customCoverFocusY,
                        )
                      : Alignment.center,
                  moduleKey: moduleKey,
                  palette: palette,
                  imageHeaderBuilder: imageHeaderBuilder,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    // 文字区底边距不要过大，否则会形成“被拉开”的视觉缝隙。
                    padding: const EdgeInsets.only(
                      top: 6,
                      left: 0,
                      right: 0,
                      bottom: 30,
                    ),
                    child: _HeroMetaColumn(
                      moduleKey: moduleKey,
                      title: title,
                      author: author,
                      sourceAuthorId: header.sourceAuthorId,
                      translationGroup: group,
                      publisherName: _nonEmpty(header.publisherName),
                      publisherId: _nonEmpty(header.publisherId),
                      foregroundColor: palette.heroInfoForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 最终的边界覆盖由父级 seam bridge 完成；这里仅保证 hero
          // 底部最后一行像素已经落到页面背景色。
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 1,
              child: ColoredBox(color: palette.headerGradientEnd),
            ),
          ),
        ],
      ),
    );
  }

  /// 当前是否在展示自定义封面（焦点仅对自定义封面生效）。
  bool _isShowingCustomCover(LibraryDetailHeader header) {
    final custom = header.customCoverLocalPath?.trim();
    return custom != null && custom.isNotEmpty;
  }

  String? _preferredLocalPath(LibraryDetailHeader header) {
    final custom = header.customCoverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = header.coverLocalPath?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? _preferredRemoteUrl(LibraryDetailHeader header) {
    final custom = header.customCoverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = header.coverImageUrl?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }
}

class _PlainHeroInfoSection extends StatelessWidget {
  const _PlainHeroInfoSection({
    required this.header,
    required this.moduleKey,
    required this.topInset,
    required this.palette,
  });

  final LibraryDetailHeader header;
  final LibraryModuleKey moduleKey;
  final double topInset;
  final UnifiedDetailPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _HeroInfoSection.heightFor(topInset),
      child: ColoredBox(
        key: const Key('unified-detail-plain-header'),
        color: palette.pageBackground,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            topInset + kToolbarHeight + 20,
            24,
            30,
          ),
          child: Align(
            key: const Key('unified-detail-plain-header-content'),
            alignment: Alignment.centerLeft,
            child: _HeroMetaColumn(
              moduleKey: moduleKey,
              title: header.title,
              author: _nonEmpty(header.author),
              sourceAuthorId: _nonEmpty(header.sourceAuthorId),
              translationGroup: _nonEmpty(header.translationGroup),
              publisherName: _nonEmpty(header.publisherName),
              publisherId: _nonEmpty(header.publisherId),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroMetaColumn extends StatelessWidget {
  const _HeroMetaColumn({
    required this.moduleKey,
    required this.title,
    required this.author,
    required this.sourceAuthorId,
    required this.translationGroup,
    required this.publisherName,
    required this.publisherId,
    required this.foregroundColor,
  });

  final LibraryModuleKey moduleKey;
  final String title;
  final String? author;
  final String? sourceAuthorId;
  final String? translationGroup;
  final String? publisherName;
  final String? publisherId;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final contributorLabel = moduleKey == LibraryModuleKey.novel
        ? '翻译者'
        : '汉化组';
    final showContributorMetadata = moduleKey != LibraryModuleKey.novel;

    return DefaultTextStyle(
      style: Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(color: foregroundColor),
      child: Column(
        key: const Key('unified-detail-hero-meta'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            key: const Key('unified-detail-hero-title'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.normal,
            ),
          ),
          if (showContributorMetadata && author != null) ...[
            const SizedBox(height: 8),
            _HeroMetadataRow(
              rowKey: const Key('unified-detail-author-row'),
              icon: Icons.person_outlined,
              semanticLabel: '作者',
              value: author!,
              foregroundColor: foregroundColor,
            ),
          ],
          if (showContributorMetadata &&
              author != null &&
              sourceAuthorId != null) ...[
            const SizedBox(height: 6),
            Text(
              'UID: $sourceAuthorId',
              key: const Key('unified-detail-source-author-id'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foregroundColor.withValues(alpha: 0.82),
              ),
            ),
          ],
          if (showContributorMetadata && translationGroup != null) ...[
            const SizedBox(height: 6),
            _HeroMetadataRow(
              rowKey: const Key('unified-detail-group-row'),
              icon: Icons.translate_outlined,
              semanticLabel: contributorLabel,
              value: translationGroup!,
              foregroundColor: foregroundColor,
            ),
          ],
          if (publisherName != null) ...[
            const SizedBox(height: 6),
            _HeroMetadataRow(
              rowKey: const Key('unified-detail-publisher-row'),
              icon: Icons.account_circle_outlined,
              semanticLabel: '发布者',
              value: publisherName!,
              foregroundColor: foregroundColor,
            ),
          ],
          if (moduleKey != LibraryModuleKey.novel && publisherId != null) ...[
            const SizedBox(height: 6),
            Text(
              'UID: $publisherId',
              key: const Key('unified-detail-publisher-id'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foregroundColor.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMetadataRow extends StatelessWidget {
  const _HeroMetadataRow({
    required this.rowKey,
    required this.icon,
    required this.semanticLabel,
    required this.value,
    required this.foregroundColor,
  });

  final Key rowKey;
  final IconData icon;
  final String semanticLabel;
  final String value;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticLabel：$value',
      excludeSemantics: true,
      child: Row(
        key: rowKey,
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _DetailHeaderBackground extends StatelessWidget {
  const _DetailHeaderBackground({
    required this.coverImageUrl,
    required this.customCoverImageUrl,
    required this.coverLocalPath,
    required this.customCoverLocalPath,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  // 可统一调节模糊强度；你觉得偏糊就继续往下调。
  static const double _blurSigma = 6;

  final String? coverImageUrl;
  final String? customCoverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final UnifiedDetailPalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 仅对背景图本身做模糊，避免把滚动中的列表内容一起模糊。
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: _blurSigma,
              sigmaY: _blurSigma,
            ),
            child: LibraryCachedImage(
              localPath: _preferredLocalPath,
              imageUrl: _preferredRemoteUrl,
              fit: BoxFit.cover,
              placeholder: Container(
                color: palette.headerPlaceholderBackground,
              ),
              headerBuilder: imageHeaderBuilder,
            ),
          ),
        ),
        DecoratedBox(
          key: const Key('unified-detail-header-gradient'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.headerGradientStart,
                palette.headerGradientMiddle,
                palette.headerGradientEnd,
              ],
              // 最后一段必须落到页面背景，避免动态主题下出现固定白边。
              stops: const [0.0, 0.72, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  String? get _preferredLocalPath {
    final custom = customCoverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = coverLocalPath?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? get _preferredRemoteUrl {
    final custom = customCoverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = coverImageUrl?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

class _HeaderActionsRow extends StatelessWidget {
  const _HeaderActionsRow({
    required this.header,
    required this.onToggleShelf,
    required this.onRefresh,
    required this.onOpenThread,
  });

  final LibraryDetailHeader header;
  final VoidCallback onToggleShelf;
  final VoidCallback onRefresh;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('unified-detail-header-actions-row'),
      // 顶部边界不留白，避免下拉时出现“被拉开”的缝隙感。
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: _ActionChip(
              icon: header.inShelf ? Icons.favorite : Icons.favorite_border,
              label: header.inShelf ? '在书架中' : '添加到书架',
              onTap: onToggleShelf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionChip(
              icon: Icons.refresh,
              label: '更新',
              onTap: onRefresh,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionChip(
              icon: Icons.open_in_new,
              label: '原帖',
              onTap: onOpenThread,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({
    required this.url,
    required this.localPath,
    required this.moduleKey,
    required this.palette,
    required this.imageHeaderBuilder,
    this.alignment = Alignment.center,
  });

  final String? url;
  final String? localPath;
  final LibraryModuleKey moduleKey;
  final UnifiedDetailPalette palette;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  /// `BoxFit.cover` 下的对齐点（自定义封面焦点）。默认居中。
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 120,
        height: 168,
        child:
            (url == null || url!.trim().isEmpty) &&
                (localPath == null || localPath!.trim().isEmpty)
            ? Container(
                color: palette.headerPlaceholderBackground,
                child: moduleKey == LibraryModuleKey.novel
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '小说无封面',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      )
                    : const Icon(Icons.image_not_supported_outlined),
              )
            : LibraryCachedImage(
                localPath: localPath,
                imageUrl: url,
                fit: BoxFit.cover,
                alignment: alignment,
                placeholder: Container(
                  color: palette.headerPlaceholderBackground,
                  child: const Icon(Icons.broken_image_outlined),
                ),
                headerBuilder: imageHeaderBuilder,
              ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
