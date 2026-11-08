part of 'thread_detail_widgets.dart';

/// Explicit endpoint demand shares normal preparation/cache/Host inputs. The
/// existing lazy list and its mounted bodies keep their normal scrolling path.
mixin _ThreadNativeEndpointPreparation
    on ConsumerState<ThreadDetailContent>, _ThreadDetailEndpointNavigation {
  ThreadBodyPresentationStore get _wholeBodyPresentations;
  bool get _isLowRamDevice;
  @override
  List<ThreadDetailPostProjection> get _postProjections;
  @override
  GlobalKey get _viewportKey;
  double? _fallbackAspectRatioForBlockImage(
    ThreadPost post,
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
  );
  void _handleBlockImageResolved(
    ThreadPost post,
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  );

  final _nativePreloads = ForumNativeBodyFlowPreloads();
  final _nativePreparationJobs = <_NativeEndpointJob>{};
  Object? _nativePreparationLayout;

  @override
  void _cancelNativePreparation() {
    for (final job in _nativePreparationJobs.toList()) {
      job.close();
    }
    _nativePreparationJobs.clear();
    _nativePreloads.cancel();
  }

  @override
  void _retireNativeEndpoint(bool Function() guard) {
    // An old navigation's finally must not retire a newer navigation's work.
    if (!_nativePreloads.isCurrent(guard)) return;
    _cancelNativePreparation();
    if (mounted) setState(() {});
  }

  @override
  Future<ThreadDetailEndpointNavigationResult> _prepareNativeEndpoint(
    ThreadDetailQuickScrollTarget target,
    bool Function() guard,
  ) async {
    if (widget.bodyReadingCoordinator != null || _postProjections.isEmpty) {
      return ThreadDetailEndpointNavigationResult.unavailable;
    }
    final box = _viewportKey.currentContext?.findRenderObject();
    final font = ref.read(forumHtmlReaderFontBindingProvider);
    if (box is! RenderBox || !box.hasSize || !font.isReady) {
      return ThreadDetailEndpointNavigationResult.unavailable;
    }
    final width =
        box.size.width -
        2 * ForumContentSpacing.pageHorizontal -
        2 * ForumContentSpacing.postBodyHorizontal;
    if (!width.isFinite || width <= 0) {
      return ThreadDetailEndpointNavigationResult.unavailable;
    }
    _cancelNativePreparation();
    _nativePreloads.begin(guard);
    final layout = _nativePreparationLayout;
    final viewport = box.size;
    bool current() =>
        mounted &&
        guard() &&
        _nativePreloads.isCurrent(guard) &&
        _nativePreparationLayout == layout &&
        box.attached &&
        box.hasSize &&
        box.size == viewport;
    final bottom = target == ThreadDetailQuickScrollTarget.bottom;
    final posts = bottom
        ? _postProjections.reversed.toList()
        : _postProjections;
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final themeData = Theme.of(context);
    final theme = const ForumHtmlRenderThemeFactory().fromThreadPalette(
      palette: palette,
      brightness: themeData.brightness,
    );
    final style = resolveForumHtmlReaderTextStyle(
      context,
      preferences: font.preferences,
      theme: theme,
      font: font.resolvedFont,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.localeOf(context);
    final inherited = DefaultTextStyle.of(context).style.merge(
      themeData.textTheme.bodyMedium?.copyWith(
        color: palette.bodyText,
        height: 1.5,
      ),
    );
    final tid = widget.state.tid, referer = widget.imageReferer;
    final precache = widget.htmlImagePrecacheService;
    final cache = _wholeBodyPresentations.nativeCache;
    final targetReady = Completer<void>();
    // Avatar + header padding give a conservative lower bound on each card.
    final count = (viewport.height / 50 + 1).ceil().clamp(
      1,
      _isLowRamDevice ? 6 : 12,
    );
    var remainingCodeUnits = (_isLowRamDevice ? 1 : 2) << 20;
    unawaited(() async {
      try {
        for (final post in posts.take(count)) {
          if (!current()) break;
          final html = post.displayPost.message.trim();
          if (html.length > remainingCodeUnits) break;
          remainingCodeUnits -= html.length;
          if (html.isEmpty) continue;
          final job = _NativeEndpointJob();
          _nativePreparationJobs.add(job);
          try {
            final request = ForumHtmlPreparationRequest(
              html: html,
              preferences: font.preferences,
              theme: theme,
              sourceId: post.sourcePost.pid.trim(),
              threadId: tid,
              imageCacheOwnerId: tid,
              preparer: const DefaultForumHtmlRenderPreparer(
                enablePlainTextLinks: true,
              ),
            );
            final presentation = _wholeBodyPresentations
                .obtain(post.sourcePost.pid, post.displayPost.message)
                .prepareForLayout((
                  request.identity,
                  font.preferences.renderOptions,
                  font.cacheKey,
                  style,
                  themeData,
                  inherited,
                  width,
                  scaler,
                  direction,
                  locale,
                ));
            if (presentation == null) continue;
            final prepared = await job.resolve(
              job.html,
              () => job.html.resolve(request, cache: cache),
            );
            if (!current()) break;
            final document = await job.resolve(
              job.native,
              () => job.native.resolve(
                ForumBodyPreparationInput(
                  html: prepared.preparedHtml,
                  sourceId: prepared.sequence.sourceId,
                  conversionIdentity: 'prepared-forum-body',
                ),
                owner: job,
                cache: cache,
              ),
            );
            if (!current()) break;
            final existing = _nativePreloads.peek(request.identity);
            final resourceIdentity = (tid, referer, precache);
            final host =
                prepared.sequence.entries.isEmpty &&
                    prepared.skippedStickerCount == 0
                ? null
                : existing?.input.resourceIdentity == resourceIdentity
                ? existing?.input.host
                : ref
                      .read(forumHtmlImageHostProvider)
                      .forContent(
                        threadId: tid,
                        imageReferer: referer,
                        imageCacheOwnerId: tid,
                        fallbackAspectRatioFor: (spec, request) =>
                            _fallbackAspectRatioForBlockImage(
                              post.sourcePost,
                              spec,
                              request,
                            ),
                        onBlockImageResolved: (spec, request, size) =>
                            _handleBlockImageResolved(
                              post.sourcePost,
                              spec,
                              request,
                              size,
                            ),
                        imagePrecacheService: precache,
                      );
            final input = ForumNativeBodyFlowInput(
              document: document,
              prepared: prepared,
              width: width,
              textStyle: style.copyWith(locale: locale),
              fontRevision: font.cacheKey.toString(),
              textScaler: scaler,
              direction: direction,
              paragraphAfter: font.preferences.typography.paragraphSpacing,
              theme: theme,
              cache: cache.paragraphs,
              host: host,
              expansion: presentation.collapseExpansion,
              presentation: presentation,
              preparationIdentity: request.identity,
              resourceIdentity: resourceIdentity,
            );
            await _nativePreloads.prepare(
              ticket: guard,
              input: input,
              bottom: bottom,
              extent: viewport.height * 2,
            );
          } catch (_) {
            // A miss/cancel keeps ordinary native scrolling available.
          } finally {
            job.close();
            _nativePreparationJobs.remove(job);
            if (!targetReady.isCompleted) targetReady.complete();
          }
        }
      } finally {
        if (!targetReady.isCompleted) targetReady.complete();
      }
    }());
    // Cold or oversized work must not turn a quick-scroll button into a wait
    // screen. Optional neighbors continue during the existing animation.
    await targetReady.future.timeout(
      const Duration(milliseconds: 250),
      onTimeout: () {},
    );
    return current()
        ? ThreadDetailEndpointNavigationResult.unavailable
        : ThreadDetailEndpointNavigationResult.retired;
  }
}

final class _NativeEndpointJob {
  final html = ForumHtmlPreparationController();
  final native = ForumBodyPreparationController();
  final _cancel = Completer<void>();
  bool _closed = false;

  Future<T> resolve<T>(Listenable controller, T? Function() read) async {
    final ready = Completer<T>();
    void check() {
      if (ready.isCompleted) return;
      try {
        final value = read();
        if (value != null) ready.complete(value);
      } catch (error, stack) {
        ready.completeError(error, stack);
      }
    }

    controller.addListener(check);
    try {
      if (_closed) throw const ForumBodyFlowPreparationCancelled();
      check();
      return await Future.any([
        ready.future,
        _cancel.future.then<T>(
          (_) => throw const ForumBodyFlowPreparationCancelled(),
        ),
      ]);
    } finally {
      controller.removeListener(check);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _cancel.complete();
    html.dispose();
    native.dispose();
  }
}
