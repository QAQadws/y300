part of 'thread_detail_widgets.dart';

/// Shared title geometry for entry states before a post list is available.
class ThreadDetailEntrySurface extends StatelessWidget {
  const ThreadDetailEntrySurface({
    super.key,
    required this.subject,
    required this.child,
  });

  final String subject;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    return SingleChildScrollView(
      // Loading/error scrolling must not restore or alter the post position.
      primary: false,
      padding: const EdgeInsets.fromLTRB(
        ForumContentSpacing.readableBodyHorizontal,
        ForumContentSpacing.listTop + ForumContentSpacing.postCardHeaderTop,
        ForumContentSpacing.readableBodyHorizontal,
        ForumContentSpacing.listBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subject.trim().isNotEmpty) ...[
            _FirstPostThreadSummary(subject: subject, palette: palette),
            const SizedBox(height: 11),
          ],
          child,
        ],
      ),
    );
  }
}

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
    final loadingLabel = AppLocalizations.of(context).threadDetailLoading;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ThreadDetailEntrySurface(
      key: const Key('thread-detail-loading'),
      subject: widget.subject,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: _showIndicator ? loadingLabel : null,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            // Reserve only the status, including its scaled text height.
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
                            key: const Key('thread-detail-loading-progress'),
                            minHeight: 2,
                            color: palette.accent,
                            backgroundColor: palette.outlineSoft,
                          ),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    loadingLabel,
                    key: const Key('thread-detail-loading-label'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
    );
  }
}
