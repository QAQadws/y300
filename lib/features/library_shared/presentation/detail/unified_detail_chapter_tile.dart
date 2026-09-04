import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/services/library_detail_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class UnifiedDetailChapterTile extends StatelessWidget {
  const UnifiedDetailChapterTile({
    super.key,
    required this.tileKey,
    required this.chapter,
    required this.subtitle,
    required this.isDownloading,
    required this.downloadIconSize,
    required this.onTap,
    required this.onLongPress,
    this.onToggleDownload,
    this.onToggleReadState,
    this.readStateMutationLocked = false,
  });

  final Key tileKey;
  final LibraryChapterItem chapter;
  final String subtitle;
  final bool isDownloading;
  final double downloadIconSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onToggleDownload;
  final Future<void> Function()? onToggleReadState;
  final bool readStateMutationLocked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleColor = chapter.isRead
        ? scheme.onSurfaceVariant
        : scheme.onSurface;
    final subtitleColor = chapter.isRead
        ? scheme.onSurfaceVariant.withAlpha(170)
        : scheme.onSurfaceVariant;

    final tile = Material(
      key: tileKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (chapter.isBookmarked) ...[
                          Icon(
                            Icons.bookmark,
                            key: ValueKey<String>(
                              'unified-detail-chapter-bookmark-indicator-${chapter.episodeId}',
                            ),
                            size: 20,
                            color: scheme.primary,
                            semanticLabel: l10n.libraryChapterBookmarkSemantics,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            LibraryDetailTextResolver.chapterTitle(
                              l10n,
                              chapter.title,
                              chapter.sourceTid,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: titleColor,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _ChapterSubtitle(
                      subtitle,
                      episodeId: chapter.episodeId,
                      progress: chapter.progressInfo,
                      style:
                          theme.textTheme.bodySmall?.copyWith(
                            color: subtitleColor,
                          ) ??
                          TextStyle(color: subtitleColor),
                    ),
                  ],
                ),
              ),
              if (onToggleDownload != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: isDownloading
                      ? l10n.libraryChapterDownloading
                      : chapter.isDownloaded
                      ? l10n.libraryChapterDownloadedDelete
                      : l10n.libraryChapterDownload,
                  iconSize: downloadIconSize,
                  onPressed: isDownloading ? null : onToggleDownload,
                  icon: isDownloading
                      ? SizedBox(
                          width: downloadIconSize,
                          height: downloadIconSize,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.2,
                          ),
                        )
                      : FaIcon(
                          chapter.isDownloaded
                              ? FontAwesomeIcons.solidCircleDown
                              : FontAwesomeIcons.circleDown,
                          size: downloadIconSize,
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final toggleReadState = onToggleReadState;
    if (toggleReadState == null) {
      return tile;
    }
    final actionLabel = chapter.isRead
        ? l10n.libraryChapterClearReadState
        : l10n.libraryChapterMarkRead;
    final actionIcon = chapter.isRead ? Icons.remove_done : Icons.done;
    final backgroundColor = chapter.isRead
        ? scheme.secondaryContainer
        : scheme.primaryContainer;
    final foregroundColor = chapter.isRead
        ? scheme.onSecondaryContainer
        : scheme.onPrimaryContainer;

    return _BoundedReadStateSwipe(
      key: ValueKey<String>(
        'unified-detail-chapter-read-swipe-${chapter.episodeId}',
      ),
      foregroundKey: ValueKey<String>(
        'unified-detail-chapter-read-swipe-foreground-${chapter.episodeId}',
      ),
      locked: readStateMutationLocked,
      onTriggered: toggleReadState,
      background: ColoredBox(
        color: backgroundColor,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(actionIcon, size: 20, color: foregroundColor),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      actionLabel,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foregroundColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: tile,
    );
  }
}

class _BoundedReadStateSwipe extends StatefulWidget {
  const _BoundedReadStateSwipe({
    super.key,
    required this.foregroundKey,
    required this.locked,
    required this.onTriggered,
    required this.background,
    required this.child,
  });

  final Key foregroundKey;
  final bool locked;
  final Future<void> Function() onTriggered;
  final Widget background;
  final Widget child;

  @override
  State<_BoundedReadStateSwipe> createState() => _BoundedReadStateSwipeState();
}

class _BoundedReadStateSwipeState extends State<_BoundedReadStateSwipe>
    with SingleTickerProviderStateMixin {
  static const double _maxDragFraction = 1 / 3;
  static const double _activationFraction = _maxDragFraction * 0.8;

  late final AnimationController _returnController;
  Animation<double>? _returnAnimation;
  double _dragFraction = 0;
  bool _isExecuting = false;

  double get _visibleFraction => _returnAnimation?.value ?? _dragFraction;

  bool get _interactionLocked =>
      widget.locked || _isExecuting || _returnController.isAnimating;

  @override
  void initState() {
    super.initState();
    _returnController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed || !mounted) {
            return;
          }
          setState(() {
            _dragFraction = 0;
            _returnAnimation = null;
          });
        });
  }

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }

  void _updateDrag(DragUpdateDetails details, double width) {
    if (_interactionLocked || width <= 0) {
      return;
    }
    setState(() {
      _dragFraction = (_dragFraction + details.delta.dx / width)
          .clamp(0, _maxDragFraction)
          .toDouble();
    });
  }

  void _finishDrag({required bool allowTrigger}) {
    if (_interactionLocked) {
      return;
    }
    final shouldTrigger = allowTrigger && _dragFraction >= _activationFraction;
    _returnAnimation = Tween<double>(begin: _dragFraction, end: 0).animate(
      CurvedAnimation(parent: _returnController, curve: Curves.easeOutCubic),
    );
    _returnController.forward(from: 0);
    if (shouldTrigger) {
      _executeAction();
    }
  }

  Future<void> _executeAction() async {
    setState(() {
      _isExecuting = true;
    });
    try {
      await widget.onTriggered();
    } finally {
      if (mounted) {
        setState(() {
          _isExecuting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _returnController,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final revealWidth = width.isFinite ? width * _visibleFraction : 0.0;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => _updateDrag(details, width),
              onHorizontalDragEnd: (_) => _finishDrag(allowTrigger: true),
              onHorizontalDragCancel: () => _finishDrag(allowTrigger: false),
              child: ClipRect(
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    if (revealWidth > 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: revealWidth,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: width * _maxDragFraction,
                            maxWidth: width * _maxDragFraction,
                            child: SizedBox(
                              width: width * _maxDragFraction,
                              child: widget.background,
                            ),
                          ),
                        ),
                      ),
                    FractionalTranslation(
                      key: widget.foregroundKey,
                      translation: Offset(_visibleFraction, 0),
                      child: child!,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      child: widget.child,
    );
  }
}

class _ChapterSubtitle extends StatelessWidget {
  const _ChapterSubtitle(
    this.subtitle, {
    required this.episodeId,
    required this.progress,
    required this.style,
  });

  final String episodeId;
  final String subtitle;
  final LibraryChapterProgressInfo? progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    if (progress == null) {
      return Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final progressStyle = style.copyWith(
      color: (style.color ?? Theme.of(context).colorScheme.onSurfaceVariant)
          .withAlpha(150),
    );
    final progressLabel = LibraryDetailTextResolver.chapterProgress(
      AppLocalizations.of(context),
      progress,
    );
    final text = RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: subtitle),
          const TextSpan(text: '  ·  '),
          TextSpan(text: progressLabel, style: progressStyle),
        ],
      ),
    );
    return Semantics(
      key: ValueKey<String>(
        'unified-detail-chapter-inline-progress-$episodeId',
      ),
      label: AppLocalizations.of(
        context,
      ).libraryChapterProgressSemantics(subtitle, progressLabel),
      child: ExcludeSemantics(child: text),
    );
  }
}
