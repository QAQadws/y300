import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

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
                  '加载失败：$message',
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
                child: const Text('重试'),
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
          final expandable = _exceedsCollapsedLines(
            context: context,
            maxWidth: constraints.maxWidth,
            style: textStyle,
          );
          return Semantics(
            button: expandable,
            onTap: expandable ? onToggle : null,
            child: InkWell(
              key: const Key('unified-detail-intro-toggle'),
              onTap: expandable ? onToggle : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('简介', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: Stack(
                        children: [
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeInOutCubic,
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: expanded && expandable ? 22 : 0,
                              ),
                              child: _buildIntroText(
                                style: textStyle,
                                expandable: expandable,
                              ),
                            ),
                          ),
                          if (expandable)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: -2,
                              child: IgnorePointer(
                                child: Center(
                                  child: AnimatedRotation(
                                    key: const Key(
                                      'unified-detail-intro-arrow',
                                    ),
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
                            ),
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

  Widget _buildIntroText({required TextStyle style, required bool expandable}) {
    final text = Text(
      intro,
      key: const Key('unified-detail-intro-text'),
      maxLines: expanded ? null : 3,
      overflow: TextOverflow.clip,
      style: style,
    );
    if (expanded || !expandable) {
      return text;
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
      child: text,
    );
  }

  bool _exceedsCollapsedLines({
    required BuildContext context,
    required double maxWidth,
    required TextStyle style,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return false;
    }
    final painter = TextPainter(
      text: TextSpan(text: intro, style: style),
      maxLines: 3,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }
}

class UnifiedDetailTagStrip extends StatelessWidget {
  const UnifiedDetailTagStrip({
    super.key,
    required this.sourceTagName,
    required this.sourceTypeId,
    required this.customTags,
  });

  final String? sourceTagName;
  final String? sourceTypeId;
  final List<LibraryTag> customTags;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = _sourceLabel();
    final labels = <String>[
      ?sourceLabel,
      ...customTags
          .map((tag) => tag.name.trim())
          .where((name) => name.isNotEmpty),
    ];
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      key: const Key('unified-detail-tag-strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _TagChip(label: labels[i]),
            if (i != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
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
      constraints: const BoxConstraints(minHeight: 30, maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
