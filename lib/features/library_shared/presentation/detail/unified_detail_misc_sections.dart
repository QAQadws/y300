import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/services/library_detail_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class UnifiedDetailErrorPanel extends StatelessWidget {
  const UnifiedDetailErrorPanel({
    super.key,
    required this.message,
    required this.topPadding,
    required this.onRetry,
  });

  final String message;
  final double topPadding;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('unified-detail-error-panel'),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer.withAlpha(120),
          border: Border.all(color: scheme.error.withAlpha(90)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).libraryDetailLoadFailed(
                    LibraryDetailTextResolver.safeError(
                      AppLocalizations.of(context),
                      message,
                    ),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('unified-detail-error-retry'),
                onPressed: onRetry,
                child: Text(AppLocalizations.of(context).commonRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UnifiedDetailIntroSection extends StatelessWidget {
  const UnifiedDetailIntroSection({
    super.key,
    required this.intro,
    required this.expanded,
    required this.onToggle,
  });

  final String intro;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    return Padding(
      key: const Key('unified-detail-intro-section'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textLayout = _measureTextLayout(
            context: context,
            maxWidth: constraints.maxWidth,
            style: textStyle,
          );
          final expandable = textLayout.expandable;
          return Semantics(
            button: expandable,
            onTap: expandable ? onToggle : null,
            child: GestureDetector(
              key: const Key('unified-detail-intro-toggle'),
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: expandable ? onToggle : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).libraryDetailIntro,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AnimatedIntroTextViewport(
                            intro: intro,
                            style: textStyle,
                            expanded: expanded,
                            expandable: expandable,
                            collapsedHeight: textLayout.collapsedHeight,
                            expandedHeight: textLayout.expandedHeight,
                          ),
                          if (expandable) ...[
                            const SizedBox(height: 2),
                            IgnorePointer(
                              child: Center(
                                child: AnimatedRotation(
                                  key: const Key('unified-detail-intro-arrow'),
                                  turns: expanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeInOutCubic,
                                  child: Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 24,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  _IntroTextLayout _measureTextLayout({
    required BuildContext context,
    required double maxWidth,
    required TextStyle style,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return const _IntroTextLayout(
        expandable: false,
        collapsedHeight: 0,
        expandedHeight: 0,
      );
    }
    final collapsedPainter = TextPainter(
      text: TextSpan(text: intro, style: style),
      maxLines: 3,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: maxWidth);
    final expandedPainter = TextPainter(
      text: TextSpan(text: intro, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: maxWidth);
    final layout = _IntroTextLayout(
      expandable: collapsedPainter.didExceedMaxLines,
      collapsedHeight: collapsedPainter.height,
      expandedHeight: expandedPainter.height,
    );
    collapsedPainter.dispose();
    expandedPainter.dispose();
    return layout;
  }
}

class _AnimatedIntroTextViewport extends StatelessWidget {
  const _AnimatedIntroTextViewport({
    required this.intro,
    required this.style,
    required this.expanded,
    required this.expandable,
    required this.collapsedHeight,
    required this.expandedHeight,
  });

  final String intro;
  final TextStyle style;
  final bool expanded;
  final bool expandable;
  final double collapsedHeight;
  final double expandedHeight;

  @override
  Widget build(BuildContext context) {
    final targetHeight = expanded || !expandable
        ? expandedHeight
        : collapsedHeight;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetHeight),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      builder: (context, height, child) {
        final viewport = SizedBox(
          key: const Key('unified-detail-intro-viewport'),
          height: height,
          child: ClipRect(
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        );
        if (expanded || !expandable) {
          return viewport;
        }
        return ShaderMask(
          key: const Key('unified-detail-intro-fade'),
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.66, 1],
          ).createShader(bounds),
          child: viewport,
        );
      },
      child: Text(
        intro,
        key: const Key('unified-detail-intro-text'),
        overflow: TextOverflow.clip,
        style: style,
      ),
    );
  }
}

class _IntroTextLayout {
  const _IntroTextLayout({
    required this.expandable,
    required this.collapsedHeight,
    required this.expandedHeight,
  });

  final bool expandable;
  final double collapsedHeight;
  final double expandedHeight;
}

class UnifiedDetailTagStrip extends StatelessWidget {
  const UnifiedDetailTagStrip({
    super.key,
    required this.sourceTagName,
    required this.sourceTypeId,
  });

  final String? sourceTagName;
  final String? sourceTypeId;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = _sourceLabel();
    if (sourceLabel == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      key: const Key('unified-detail-tag-strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(children: [_TagChip(label: sourceLabel)]),
    );
  }

  String? _sourceLabel() {
    final tagName = sourceTagName?.trim();
    if (tagName != null && tagName.isNotEmpty) {
      return tagName;
    }
    final typeId = sourceTypeId?.trim();
    if (typeId != null && typeId.isNotEmpty) {
      return 'typeid=$typeId';
    }
    return null;
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('unified-detail-source-tag'),
      constraints: const BoxConstraints(minHeight: 30, maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
