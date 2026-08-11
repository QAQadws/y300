import 'package:flutter/material.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

class ForumSearchResultCard extends StatefulWidget {
  const ForumSearchResultCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final DiscuzSearchResultItem item;
  final VoidCallback onTap;

  @override
  State<ForumSearchResultCard> createState() => _ForumSearchResultCardState();
}

class _ForumSearchResultCardState extends State<ForumSearchResultCard> {
  static const double _cornerRadius = 12;

  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = ForumDisplayThemePalette.resolve(Theme.of(context));
    final item = widget.item;
    final metadata = _metadataText(item);

    return AnimatedScale(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      scale: _isPressed ? 0.985 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_cornerRadius),
          boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
        ),
        child: Material(
          color: palette.surfaceContainerLow,
          borderRadius: BorderRadius.circular(_cornerRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(_cornerRadius),
            onHighlightChanged: (isHighlighted) {
              if (_isPressed != isHighlighted) {
                setState(() => _isPressed = isHighlighted);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: _isPressed
                    ? Color.alphaBlend(
                        palette.stateLayer,
                        palette.surfaceContainerLow,
                      )
                    : palette.surfaceContainerLow,
                borderRadius: BorderRadius.circular(_cornerRadius),
              ),
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    key: Key('forum-search-result-title-${item.tid}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: palette.threadTitle,
                      height: 1.28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (metadata != null)
                        Expanded(
                          child: Text(
                            metadata,
                            key: Key(
                              'forum-search-result-metadata-${item.tid}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: palette.softText,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (metadata != null) const SizedBox(width: 10),
                      Text(
                        AppLocalizations.of(context).searchResultTid(item.tid),
                        key: Key('forum-search-result-tid-${item.tid}'),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: palette.softText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _metadataText(DiscuzSearchResultItem item) {
    final values = <String>[
      if (item.author?.trim().isNotEmpty == true) item.author!.trim(),
      if (item.timeText?.trim().isNotEmpty == true) item.timeText!.trim(),
    ];
    return values.isEmpty ? null : values.join(' · ');
  }
}
