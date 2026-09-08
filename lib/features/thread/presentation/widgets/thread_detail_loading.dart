part of 'thread_detail_widgets.dart';

/// A quiet first-load surface using the title already supplied by the route.
/// It never loads media or delays ready content to finish an animation.
class ThreadDetailLoading extends StatefulWidget {
  const ThreadDetailLoading({super.key, required this.subject});

  final String subject;

  @override
  State<ThreadDetailLoading> createState() => _ThreadDetailLoadingState();
}

class _ThreadDetailLoadingState extends State<ThreadDetailLoading> {
  Timer? _indicatorTimer;
  bool _showIndicator = false;

  @override
  void initState() {
    super.initState();
    // Fast cache/network reads should not flash an indeterminate indicator.
    _indicatorTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _showIndicator = true);
      }
    });
  }

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final placeholderColor = Color.alphaBlend(
      palette.outlineSoft,
      palette.card,
    );
    final loadingLabel = AppLocalizations.of(context).threadDetailLoading;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SingleChildScrollView(
      key: const Key('thread-detail-loading'),
      // Do not share the actual post list's controller, position or image tasks.
      primary: false,
      padding: const EdgeInsets.fromLTRB(
        ForumContentSpacing.pageHorizontal,
        ForumContentSpacing.listTop,
        ForumContentSpacing.pageHorizontal,
        ForumContentSpacing.listBottom,
      ),
      child: DecoratedBox(
        decoration: _cardDecoration(palette),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ForumContentSpacing.postBodyHorizontal,
            ForumContentSpacing.postCardHeaderTop,
            ForumContentSpacing.postBodyHorizontal,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.subject.trim().isNotEmpty)
                _FirstPostThreadSummary(
                  subject: widget.subject,
                  palette: palette,
                )
              else
                ExcludeSemantics(
                  child: _ThreadLoadingLines(
                    color: placeholderColor,
                    widths: const [0.84, 0.56],
                    height: 17,
                  ),
                ),
              const SizedBox(height: 11),
              ExcludeSemantics(
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: placeholderColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _ThreadLoadingLines(
                        color: placeholderColor,
                        widths: const [0.24, 0.38],
                        height: 8,
                        gap: 8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ExcludeSemantics(
                child: _ThreadLoadingLines(
                  color: placeholderColor,
                  widths: const [0.96, 0.90, 0.98, 0.62],
                ),
              ),
              const SizedBox(height: 24),
              ExcludeSemantics(
                child: _ThreadLoadingLines(
                  color: placeholderColor,
                  widths: const [0.94, 0.86, 0.50],
                ),
              ),
              const SizedBox(height: 24),
              // Reserve space so the delayed status does not resize the card.
              Semantics(
                container: true,
                liveRegion: true,
                label: _showIndicator ? loadingLabel : null,
                child: ExcludeSemantics(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!reduceMotion) ...[
                          SizedBox(
                            width: 32,
                            child: !_showIndicator
                                ? null
                                : LinearProgressIndicator(
                                    key: const Key(
                                      'thread-detail-loading-progress',
                                    ),
                                    minHeight: 2,
                                    color: palette.accent,
                                    backgroundColor: placeholderColor,
                                  ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            loadingLabel,
                            key: const Key('thread-detail-loading-label'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _showIndicator
                                      ? palette.muted
                                      : Colors.transparent,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadLoadingLines extends StatelessWidget {
  const _ThreadLoadingLines({
    required this.color,
    required this.widths,
    this.height = 10,
    this.gap = 14,
  });

  final Color color;
  final List<double> widths;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < widths.length; index++) ...[
          if (index > 0) SizedBox(height: gap),
          FractionallySizedBox(
            widthFactor: widths[index],
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
