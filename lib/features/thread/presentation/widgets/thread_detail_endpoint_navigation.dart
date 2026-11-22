part of 'thread_detail_widgets.dart';

/// Reuses the entry-centered viewport without knowing intervening chunk heights.
mixin _ThreadDetailEndpointNavigation on ConsumerState<ThreadDetailContent> {
  // These fwfh/platform controls still own widget-local state. Forum folds,
  // inline images and ordinary typography use the page presentation store.
  static final _widgetLocalMarkup = RegExp(
    r'<(?:details|audio|video|iframe|input|select|textarea|form|object|embed)(?=[\s/>])',
    caseSensitive: false,
  );

  ThreadDetailPreparedBodyStore get _preparedBodies;
  ThreadPostViewportAnchorCoordinator get _projectionAnchorCoordinator;
  set _pendingChunkAnchor(ThreadPostViewportAnchorSnapshot? value);
  GlobalKey get _targetCenterKey;
  set _targetCenterKey(GlobalKey value);
  GlobalKey get _viewportKey;
  List<ThreadDetailPostProjection> get _postProjections;
  Object? get _renderLayoutIdentity;
  bool get _canChunkBodies;
  bool _isCurrentPreparedRequest(ForumHtmlPreparationRequest request);

  final _endpointBoundaryKey = GlobalKey(debugLabel: 'thread-page-endpoint');
  ThreadDetailQuickScrollTarget? _endpointTarget;
  double _endpointArrivalDistance = 0;
  int _endpointGeneration = 0;
  int _endpointViewRevision = 0;
  ({
    bool Function() current,
    double arrivalDistance,
    ThreadDetailQuickScrollTarget? target,
    int revision,
    GlobalKey center,
  })?
  _pendingEndpointBuild;

  void _prepareEndpointBuild() {
    final pending = _pendingEndpointBuild;
    _pendingEndpointBuild = null;
    if (pending == null) return;
    if (pending.current()) {
      _endpointArrivalDistance = pending.arrivalDistance;
      return;
    }
    // A drag/cancel before the next build must not publish a queued rebase.
    _endpointTarget = pending.target;
    _endpointViewRevision = pending.revision;
    _targetCenterKey = pending.center;
  }

  void _bindEndpointNavigation() => widget.quickScrollCoordinator
      ?.bindEndpointNavigator(this, _navigateToEndpoint);

  void _updateEndpointNavigation(ThreadDetailContent previous) {
    final ownerChanged =
        previous.state.tid != widget.state.tid ||
        previous.state.currentPage != widget.state.currentPage ||
        previous.targetPid != widget.targetPid ||
        previous.landing != widget.landing ||
        !identical(previous.scrollController, widget.scrollController) ||
        previous.bodyReadingCoordinator != widget.bodyReadingCoordinator ||
        previous.enableBodyChunking != widget.enableBodyChunking;
    final postsChanged =
        previous.state.posts.length != widget.state.posts.length ||
        List.generate(widget.state.posts.length, (index) => index).any(
          (index) =>
              index >= previous.state.posts.length ||
              previous.state.posts[index].pid !=
                  widget.state.posts[index].pid ||
              previous.state.posts[index].message !=
                  widget.state.posts[index].message,
        );
    if (ownerChanged ||
        postsChanged ||
        previous.projection?.displayIdentity !=
            widget.projection?.displayIdentity) {
      _endpointGeneration++;
    }
    if (ownerChanged) {
      _pendingEndpointBuild = null;
      _endpointTarget = null;
      _endpointViewRevision++;
      _targetCenterKey = GlobalKey(debugLabel: 'thread-detail-target-center');
    }
    if (!identical(
      previous.quickScrollCoordinator,
      widget.quickScrollCoordinator,
    )) {
      previous.quickScrollCoordinator?.unbindEndpointNavigator(this);
      _endpointGeneration++;
      _bindEndpointNavigation();
    }
  }

  void _disposeEndpointNavigation() {
    _endpointGeneration++;
    widget.quickScrollCoordinator?.unbindEndpointNavigator(this);
  }

  bool _canRebaseToEndpoint() {
    if (!_canChunkBodies || _postProjections.isEmpty) return false;
    for (final post in _postProjections) {
      if (_widgetLocalMarkup.hasMatch(post.displayPost.message)) return false;
      final body = _preparedBodies[post.sourcePost.pid];
      if (body != null && !_isCurrentPreparedRequest(body.request)) {
        return false;
      }
    }
    // Whole bodies now retain folds, image geometry/fades and measured height
    // in the page-owned presentation store. Rebase their entries just like
    // chunks; requiring every intervening body to be splittable forces a full
    // distance scroll through unrelated complex replies.
    return true;
  }

  Future<ThreadDetailEndpointNavigationResult> _navigateToEndpoint({
    required ThreadDetailQuickScrollTarget target,
    required bool animate,
    required Duration duration,
    required bool Function() isCurrent,
  }) async {
    if (!_canRebaseToEndpoint()) {
      return ThreadDetailEndpointNavigationResult.unavailable;
    }
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) {
      return ThreadDetailEndpointNavigationResult.unavailable;
    }
    _prepareEndpointBuild();
    final generation = ++_endpointGeneration;
    final layoutIdentity = _renderLayoutIdentity;
    bool current() =>
        mounted &&
        generation == _endpointGeneration &&
        isCurrent() &&
        layoutIdentity == _renderLayoutIdentity &&
        identical(controller, widget.scrollController);
    _projectionAnchorCoordinator.beginExplicitNavigation();
    _pendingChunkAnchor = null;
    final position = controller.position;
    final remainingDistance = target == ThreadDetailQuickScrollTarget.top
        ? position.extentBefore
        : position.extentAfter;
    _pendingEndpointBuild = (
      current: current,
      arrivalDistance: animate
          ? remainingDistance.clamp(0.0, position.viewportDimension / 2)
          : 0.0,
      target: _endpointTarget,
      revision: _endpointViewRevision,
      center: _targetCenterKey,
    );
    setState(() {
      _endpointTarget = target;
      _endpointViewRevision++;
      // Both the ScrollPosition and sliver layout offsets belong to the old
      // center. A fresh viewport lays out only the destination neighborhood.
      _targetCenterKey = GlobalKey(debugLabel: 'thread-detail-target-center');
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!current() || !controller.hasClients) {
      return ThreadDetailEndpointNavigationResult.retired;
    }
    double destination() => target == ThreadDetailQuickScrollTarget.top
        ? controller.position.minScrollExtent
        : controller.position.maxScrollExtent;
    if (animate) {
      // Animate only the short arrival near the destination, not every lazy
      // chunk between the old position and the endpoint.
      await controller.animateTo(
        destination(),
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(destination());
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!current() || !controller.hasClients) {
        return ThreadDetailEndpointNavigationResult.retired;
      }
      final marker = _endpointBoundaryKey.currentContext?.findRenderObject();
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (marker is RenderBox &&
          marker.attached &&
          marker.hasSize &&
          viewport is RenderBox &&
          viewport.attached &&
          viewport.hasSize &&
          (controller.position.pixels - destination()).abs() <= 1) {
        final top = marker.localToGlobal(Offset.zero, ancestor: viewport).dy;
        final edge = target == ThreadDetailQuickScrollTarget.top
            ? top
            : top + marker.size.height;
        if (edge >= -1 && edge <= viewport.size.height + 1) {
          return ThreadDetailEndpointNavigationResult.reached;
        }
      }
      controller.jumpTo(destination());
    }
    return ThreadDetailEndpointNavigationResult.retired;
  }
}

class _ThreadTargetPadding extends SliverPadding {
  const _ThreadTargetPadding({
    super.key,
    required super.padding,
    required super.sliver,
    required this.initialScrollOffset,
  });

  final double initialScrollOffset;

  @override
  RenderSliverPadding createRenderObject(BuildContext context) =>
      _RenderThreadTargetPadding(
        padding: padding,
        textDirection: Directionality.of(context),
        initialScrollOffset: initialScrollOffset,
      );
}

class _RenderThreadTargetPadding extends RenderSliverPadding {
  _RenderThreadTargetPadding({
    required super.padding,
    required super.textDirection,
    required double initialScrollOffset,
  }) : _initialScrollOffset = initialScrollOffset;

  double _initialScrollOffset;

  @override
  void performLayout() {
    // Flutter applies the correction in the sliver's growth direction. This
    // starts either endpoint animation at its real offset before first paint.
    if (_initialScrollOffset > 0) {
      final correction = _initialScrollOffset - constraints.scrollOffset;
      _initialScrollOffset = 0;
      if (correction != 0) {
        geometry = SliverGeometry(scrollOffsetCorrection: correction);
        return;
      }
    }
    super.performLayout();
  }
}
