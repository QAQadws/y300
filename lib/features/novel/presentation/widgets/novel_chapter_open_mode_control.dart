import 'package:flutter/material.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/l10n/app_localizations.dart';

class NovelChapterOpenModeControl extends StatelessWidget {
  const NovelChapterOpenModeControl({
    super.key,
    required this.selectedMode,
    required this.onChanged,
  });

  final NovelChapterOpenMode selectedMode;
  final ValueChanged<NovelChapterOpenMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    const spacing = 12.0;
    const indicatorWidth = 22.0;
    // Equal-width targets let one marker follow either label at any text scale
    // without retaining render boxes or changing layout during the transition.
    return IntrinsicWidth(
      child: Stack(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: _option(
                  context,
                  NovelChapterOpenMode.reader,
                  l10n.novelOpenInReader,
                ),
              ),
              const SizedBox(width: spacing),
              Expanded(
                child: _option(
                  context,
                  NovelChapterOpenMode.sourcePost,
                  l10n.novelOpenSourcePost,
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            height: 2,
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) => Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        (constraints.maxWidth - spacing) / 4 -
                        indicatorWidth / 2,
                  ),
                  child: AnimatedAlign(
                    alignment: selectedMode == NovelChapterOpenMode.reader
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: SizedBox(
                      key: const Key('novel-chapter-open-mode-indicator'),
                      width: indicatorWidth,
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: onChanged != null
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context,
    NovelChapterOpenMode mode,
    String label,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = selectedMode == mode;
    final enabled = onChanged != null;
    return TextButton(
      onPressed: enabled
          ? () {
              if (!selected) onChanged!(mode);
            }
          : null,
      style: TextButton.styleFrom(
        foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        backgroundColor: Colors.transparent,
        overlayColor: scheme.primary.withValues(alpha: 0.08),
        minimumSize: const Size(56, 48),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Text(label),
      ),
    );
  }
}
