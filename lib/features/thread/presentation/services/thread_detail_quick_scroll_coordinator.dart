import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

enum ThreadDetailQuickScrollTarget { top, bottom }

enum ThreadDetailEndpointNavigationResult { unavailable, reached, retired }

typedef ThreadDetailEndpointNavigator =
    Future<ThreadDetailEndpointNavigationResult> Function({
      required ThreadDetailQuickScrollTarget target,
      required bool animate,
      required Duration duration,
      required bool Function() isCurrent,
    });

/// Owns the transient direction and endpoint state for thread quick scrolling.
///
/// The coordinator observes only the page's primary scrollable. It does not own
/// the [ScrollController], load another thread page, or persist reading state.
final class ThreadDetailQuickScrollCoordinator extends ChangeNotifier {
  ThreadDetailQuickScrollCoordinator({
    required ScrollController scrollController,
    this.animationDuration = const Duration(milliseconds: 260),
    this.endpointTolerance = 1,
    this.onUserNavigation,
    this.onNavigationStarted,
  }) : _scrollController = scrollController;

  final ScrollController _scrollController;
  final Duration animationDuration;
  final double endpointTolerance;
  final VoidCallback? onUserNavigation;
  final VoidCallback? onNavigationStarted;

  ThreadDetailQuickScrollTarget _target = ThreadDetailQuickScrollTarget.bottom;
  bool _isScrollable = false;
  bool _isNavigating = false;
  bool _navigationInterrupted = false;
  bool _isDisposed = false;
  int _navigationGeneration = 0;
  _EndpointBinding? _endpointBinding;

  void bindEndpointNavigator(
    Object owner,
    ThreadDetailEndpointNavigator navigate,
  ) {
    _endpointBinding = _EndpointBinding(owner, navigate);
  }

  void unbindEndpointNavigator(Object owner) {
    if (identical(_endpointBinding?.owner, owner)) _endpointBinding = null;
  }

  void cancelNavigation() {
    _navigationGeneration++;
    _navigationInterrupted = true;
    final wasNavigating = _isNavigating;
    _isNavigating = false;
    if (wasNavigating && _scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.pixels);
    }
    if (wasNavigating && !_isDisposed) notifyListeners();
  }

  ThreadDetailQuickScrollTarget get target => _target;
  bool get isScrollable => _isScrollable;
  bool get isNavigating => _isNavigating;

  void updateUserDirection(ScrollDirection direction) {
    if (_isDisposed) {
      return;
    }
    if (_isNavigating && direction != ScrollDirection.idle) {
      _navigationInterrupted = true;
    }
    switch (direction) {
      case ScrollDirection.forward:
        _setTarget(ThreadDetailQuickScrollTarget.top);
      case ScrollDirection.reverse:
        _setTarget(ThreadDetailQuickScrollTarget.bottom);
      case ScrollDirection.idle:
        return;
    }
  }

  void updateMetrics(ScrollMetrics metrics) {
    if (_isDisposed) {
      return;
    }
    final min = metrics.minScrollExtent;
    final max = metrics.maxScrollExtent;
    final pixels = metrics.pixels;
    final hasFiniteRange = min.isFinite && max.isFinite && pixels.isFinite;
    final isScrollable = hasFiniteRange && max - min > endpointTolerance;

    var changed = _isScrollable != isScrollable;
    _isScrollable = isScrollable;

    if (isScrollable) {
      final nextTarget = pixels <= min + endpointTolerance
          ? ThreadDetailQuickScrollTarget.bottom
          : pixels >= max - endpointTolerance
          ? ThreadDetailQuickScrollTarget.top
          : _target;
      if (_target != nextTarget) {
        _target = nextTarget;
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  Future<void> navigate({required bool animate}) async {
    if (_isDisposed ||
        _isNavigating ||
        !_isScrollable ||
        !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    updateMetrics(position);
    if (!_isScrollable) {
      return;
    }

    final requestedTarget = _target;
    final targetOffset = switch (requestedTarget) {
      ThreadDetailQuickScrollTarget.top => position.minScrollExtent,
      ThreadDetailQuickScrollTarget.bottom => position.maxScrollExtent,
    };
    final sourceOffset = position.pixels;
    if ((sourceOffset - targetOffset).abs() <= endpointTolerance) {
      updateMetrics(position);
      return;
    }

    _isNavigating = true;
    final generation = ++_navigationGeneration;
    bool isCurrent() => !_isDisposed && generation == _navigationGeneration;
    onNavigationStarted?.call();
    _navigationInterrupted = false;
    notifyListeners();
    try {
      final endpoint = _endpointBinding;
      if (endpoint != null) {
        final result = await endpoint.navigate(
          target: requestedTarget,
          animate: animate,
          duration: animationDuration,
          isCurrent: () =>
              isCurrent() &&
              !_navigationInterrupted &&
              identical(_endpointBinding, endpoint),
        );
        if (!identical(_endpointBinding, endpoint) ||
            !isCurrent() ||
            _navigationInterrupted ||
            result == ThreadDetailEndpointNavigationResult.retired) {
          return;
        }
        if (result == ThreadDetailEndpointNavigationResult.reached) {
          // The host may have rebased its viewport. Old and new pixel offsets
          // are not comparable; completion confirms the actual entry endpoint.
          onUserNavigation?.call();
          return;
        }
      }
      if (animate) {
        await _scrollController.animateTo(
          targetOffset,
          duration: animationDuration,
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(targetOffset);
      }
      if (isCurrent() &&
          !_navigationInterrupted &&
          _shouldSettleAtLiveEndpoint(requestedTarget, targetOffset)) {
        await _settleAtLiveEndpoint(requestedTarget, isCurrent);
      }
      if (isCurrent() &&
          !_navigationInterrupted &&
          _scrollController.hasClients &&
          (_scrollController.position.pixels - sourceOffset).abs() >
              endpointTolerance) {
        // Confirm after the final live endpoint settles. Authorizing only the
        // animation's first frame would persist its starting position.
        onUserNavigation?.call();
      }
    } catch (error) {
      // A route replacement or a new user drag may detach/cancel the position.
      // The next metrics notification will establish the new legal endpoint.
      assert(() {
        debugPrint(
          '[ThreadDetail][quick_scroll][cancelled] '
          'error=${error.runtimeType}',
        );
        return true;
      }());
    } finally {
      if (isCurrent()) {
        _isNavigating = false;
        _navigationInterrupted = false;
        if (_scrollController.hasClients) {
          updateMetrics(_scrollController.position);
        }
        notifyListeners();
      }
    }
  }

  bool _shouldSettleAtLiveEndpoint(
    ThreadDetailQuickScrollTarget requestedTarget,
    double originalTarget,
  ) {
    if (!_scrollController.hasClients) {
      return false;
    }
    final position = _scrollController.position;
    final liveTarget = switch (requestedTarget) {
      ThreadDetailQuickScrollTarget.top => position.minScrollExtent,
      ThreadDetailQuickScrollTarget.bottom => position.maxScrollExtent,
    };
    final reachedOriginal =
        (position.pixels - originalTarget).abs() <= endpointTolerance;
    final endpointMoved =
        (liveTarget - originalTarget).abs() > endpointTolerance;
    return reachedOriginal || endpointMoved;
  }

  Future<void> _settleAtLiveEndpoint(
    ThreadDetailQuickScrollTarget requestedTarget,
    bool Function() isCurrent,
  ) async {
    // Lazy HTML entries and decoded images can change the content extent while
    // a fast animation is crossing the page. Re-sample for a few frames so the
    // button never leaves the position at a stale or out-of-range endpoint.
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!isCurrent() ||
          _navigationInterrupted ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final liveTarget = switch (requestedTarget) {
        ThreadDetailQuickScrollTarget.top => position.minScrollExtent,
        ThreadDetailQuickScrollTarget.bottom => position.maxScrollExtent,
      };
      if ((position.pixels - liveTarget).abs() <= endpointTolerance) {
        return;
      }
      _scrollController.jumpTo(liveTarget);
    }
  }

  void _setTarget(ThreadDetailQuickScrollTarget value) {
    if (_target == value) {
      return;
    }
    _target = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _navigationGeneration++;
    _endpointBinding = null;
    super.dispose();
  }
}

final class _EndpointBinding {
  _EndpointBinding(this.owner, this.navigate);
  final Object owner;
  final ThreadDetailEndpointNavigator navigate;
}
