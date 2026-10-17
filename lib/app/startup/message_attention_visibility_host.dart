import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';

final messageAttentionRouteObserverProvider =
    Provider<MessageAttentionRouteObserver>((ref) {
      final observer = MessageAttentionRouteObserver();
      ref.onDispose(observer.dispose);
      return observer;
    });

/// Tracks exit overlays, including popup routes whose reverse animation does
/// not drive the underlying page's secondary animation.
final class MessageAttentionRouteObserver extends NavigatorObserver
    with ChangeNotifier {
  final Set<TransitionRoute<dynamic>> _exits = Set.identity();
  bool _disposed = false;

  bool get isTransitioning => _exits.isNotEmpty;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _watchExit(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _watchExit(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _watchExit(oldRoute);
    _changed();
  }

  void _watchExit(Route<dynamic>? route) {
    if (_disposed || route is! TransitionRoute<dynamic> || !_exits.add(route)) {
      return;
    }
    void finish() {
      if (_disposed) return;
      _exits.remove(route);
      _changed();
    }

    unawaited(
      route.completed.then<void>(
        (_) => finish(),
        onError: (Object error, StackTrace stackTrace) => finish(),
      ),
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _exits.clear();
    super.dispose();
  }
}

/// Reports actual More visibility; keeping an IndexedStack child mounted does
/// not acknowledge attention.
class MessageAttentionVisibilityHost extends ConsumerStatefulWidget {
  const MessageAttentionVisibilityHost({
    super.key,
    required this.isMoreSelected,
    required this.child,
  });

  final bool isMoreSelected;
  final Widget child;

  @override
  ConsumerState<MessageAttentionVisibilityHost> createState() =>
      _MessageAttentionVisibilityHostState();
}

class _MessageAttentionVisibilityHostState
    extends ConsumerState<MessageAttentionVisibilityHost>
    with WidgetsBindingObserver {
  final Object _visibilityOwner = Object();
  late final MessageAttentionController _controller;
  late final MessageAttentionRouteObserver _routes;
  ModalRoute<dynamic>? _route;
  Animation<double>? _entrance;
  Animation<double>? _cover;
  bool _firstFrame = false;
  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(messageAttentionControllerProvider);
    _routes = ref.read(messageAttentionRouteObserverProvider);
    _routes.addListener(_reconcile);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _firstFrame = true;
      _reconcile();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _entrance?.removeStatusListener(_animationChanged);
      _cover?.removeStatusListener(_animationChanged);
      _route = route;
      _entrance = route?.animation;
      _cover = route?.secondaryAnimation;
      _entrance?.addStatusListener(_animationChanged);
      _cover?.addStatusListener(_animationChanged);
    }
    _reconcile();
  }

  @override
  void didUpdateWidget(MessageAttentionVisibilityHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _reconcile();

  void _animationChanged(AnimationStatus status) => _reconcile();

  bool get _visible {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        _firstFrame &&
        widget.isMoreSelected &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        _route?.isCurrent != false &&
        !_routes.isTransitioning &&
        (_entrance == null || _entrance!.status == AnimationStatus.completed) &&
        (_cover == null || _cover!.status == AnimationStatus.dismissed);
  }

  void _reconcile() {
    // Retire visibility immediately, including notifications during navigation
    // and build. The false transition does not publish a state change.
    if (!_visible) {
      _controller.setMoreVisible(false, visibilityOwner: _visibilityOwner);
      return;
    }
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      _controller.setMoreVisible(_visible, visibilityOwner: _visibilityOwner);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    // Owner transitions can reset the controller without remounting this host.
    ref.watch(messageAttentionStateProvider);
    _reconcile();
    return widget.child;
  }

  @override
  void dispose() {
    _controller.setMoreVisible(false, visibilityOwner: _visibilityOwner);
    _entrance?.removeStatusListener(_animationChanged);
    _cover?.removeStatusListener(_animationChanged);
    _routes.removeListener(_reconcile);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
