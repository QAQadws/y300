import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/forum_image_cache_requests.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/forum/data/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';

class ForumHomeCarousel extends StatelessWidget {
  const ForumHomeCarousel({
    super.key,
    required this.items,
    required this.headerBuilder,
    required this.onOpen,
  });

  final List<ForumHomeCarouselItem> items;
  final ImageRequestHeaderBuilder headerBuilder;
  final ValueChanged<ForumHomeCarouselItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = ForumHomeNativePalette.resolve(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: _ForumHomeCarouselBody(
        aspectRatio:
            items.first.aspectRatio ??
            ForumHomeCarouselImageProbe.fallbackAspectRatio,
        headerBuilder: headerBuilder,
        items: items,
        onOpen: onOpen,
        palette: palette,
      ),
    );
  }
}

class _ForumHomeCarouselBody extends StatelessWidget {
  const _ForumHomeCarouselBody({
    required this.aspectRatio,
    required this.headerBuilder,
    required this.items,
    required this.onOpen,
    required this.palette,
  });

  final double aspectRatio;
  final ImageRequestHeaderBuilder headerBuilder;
  final List<ForumHomeCarouselItem> items;
  final ValueChanged<ForumHomeCarouselItem> onOpen;
  final ForumHomeNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 24;
        final carouselHeight = availableWidth / aspectRatio;
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            key: const Key('forum-home-carousel'),
            width: double.infinity,
            height: carouselHeight,
            child: CarouselSlider.builder(
              itemCount: items.length,
              options: CarouselOptions(
                height: carouselHeight,
                viewportFraction: 1,
                autoPlay: items.length > 1,
                autoPlayInterval: const Duration(seconds: 3),
                autoPlayAnimationDuration: const Duration(milliseconds: 450),
                enableInfiniteScroll: items.length > 1,
                disableCenter: true,
              ),
              itemBuilder: (context, index, realIndex) {
                final item = items[index];
                return SizedBox.expand(
                  child: Material(
                    color: palette.carouselPlaceholder,
                    child: InkWell(
                      key: Key('forum-home-carousel-item-$index'),
                      onTap: () => onOpen(item),
                      child: CachedLibraryImage(
                        request: ForumImageCacheRequests.forumHeadImage(
                          url: item.imageUrl,
                        ),
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        headerBuilder: headerBuilder,
                        placeholder: ColoredBox(
                          color: palette.carouselPlaceholder,
                          child: const SizedBox.expand(),
                        ),
                        errorPlaceholder: ColoredBox(
                          color: palette.carouselPlaceholder,
                          child: const Center(
                            child: Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class ForumHomeSectionCard extends StatelessWidget {
  const ForumHomeSectionCard({
    super.key,
    required this.title,
    required this.children,
    required this.isCollapsed,
    required this.onToggle,
  });

  final String title;
  final List<Widget> children;
  final bool isCollapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = ForumHomeNativePalette.resolve(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            key: Key('forum-section-title-$title'),
            color: palette.sectionHeaderBackground,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(4),
              bottom: Radius.circular(isCollapsed ? 4 : 0),
            ),
            child: InkWell(
              key: Key('forum-section-toggle-$title'),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(4),
                bottom: Radius.circular(isCollapsed ? 4 : 0),
              ),
              onTap: onToggle,
              child: SizedBox(
                height: 54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.sectionHeaderForeground,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      _ForumHomeSectionIndicator(
                        title: title,
                        isCollapsed: isCollapsed,
                        palette: palette,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                );
              },
              child: isCollapsed
                  ? const SizedBox.shrink(
                      key: ValueKey('forum-home-section-collapsed'),
                    )
                  : DecoratedBox(
                      key: ValueKey('forum-home-section-expanded-$title'),
                      decoration: BoxDecoration(
                        color: palette.sectionBodyBackground,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(4),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForumHomeSectionIndicator extends StatelessWidget {
  const _ForumHomeSectionIndicator({
    required this.title,
    required this.isCollapsed,
    required this.palette,
  });

  final String title;
  final bool isCollapsed;
  final ForumHomeNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: isCollapsed ? 0.25 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, turns, child) {
        return RotationTransition(
          turns: AlwaysStoppedAnimation<double>(turns),
          child: child,
        );
      },
      child: Text(
        isCollapsed ? '+' : '-',
        key: Key('forum-section-indicator-$title'),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: palette.sectionHeaderForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ForumHomeForumRow extends StatelessWidget {
  const ForumHomeForumRow({
    super.key,
    required this.title,
    required this.description,
    required this.todayPosts,
    required this.isLast,
    required this.onTap,
  });

  final String title;
  final String description;
  final int todayPosts;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ForumHomeNativePalette.resolve(Theme.of(context));
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(bottom: BorderSide(color: palette.rowDivider)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 13, 10, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: textTheme.titleMedium?.copyWith(
                            color: palette.forumTitle,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (todayPosts > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '今日 $todayPosts',
                          textAlign: TextAlign.start,
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.todayText,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.descriptionText,
                        height: 1.32,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class ForumHomeNativePalette {
  const ForumHomeNativePalette({
    required this.background,
    required this.carouselPlaceholder,
    required this.sectionHeaderBackground,
    required this.sectionHeaderForeground,
    required this.sectionBodyBackground,
    required this.forumTitle,
    required this.descriptionText,
    required this.todayText,
    required this.rowDivider,
  });

  final Color background;
  final Color carouselPlaceholder;
  final Color sectionHeaderBackground;
  final Color sectionHeaderForeground;
  final Color sectionBodyBackground;
  final Color forumTitle;
  final Color descriptionText;
  final Color todayText;
  final Color rowDivider;

  static ForumHomeNativePalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    if (scheme.brightness == Brightness.dark) {
      return ForumHomeNativePalette(
        background: theme.scaffoldBackgroundColor,
        carouselPlaceholder: scheme.surfaceContainerHighest,
        sectionHeaderBackground: scheme.secondaryContainer,
        sectionHeaderForeground: scheme.onSecondaryContainer,
        sectionBodyBackground: scheme.surfaceContainer,
        forumTitle: scheme.primary,
        descriptionText: scheme.onSurfaceVariant,
        todayText: scheme.primary,
        rowDivider: scheme.outlineVariant.withValues(alpha: 0.62),
      );
    }
    return ForumHomeNativePalette(
      background: AppThemeTokens.scaffoldBackground,
      carouselPlaceholder:
          Color.lerp(
            AppThemeTokens.appBarBackground,
            AppThemeTokens.scaffoldBackground,
            0.8,
          ) ??
          AppThemeTokens.forumWebviewSectionBackground,
      sectionHeaderBackground: AppThemeTokens.appBarBackground,
      sectionHeaderForeground: AppThemeTokens.appBarForeground,
      sectionBodyBackground: AppThemeTokens.forumWebviewSectionBackground,
      forumTitle: AppThemeTokens.appBarBackground,
      descriptionText: const Color(0xFF8F949A),
      todayText: Colors.redAccent.shade200,
      rowDivider: scheme.outlineVariant.withValues(alpha: 0.58),
    );
  }
}
