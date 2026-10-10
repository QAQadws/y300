import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/forum_link_opener.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';

import 'forum_clipboard_link_policy.dart';
import 'forum_clipboard_route_observer.dart';
import 'forum_clipboard_runtime.dart';
import 'forum_clipboard_snack_bar_presenter.dart';

/// The sole main-shell UI host. Routes, keyboard and startup readiness gate an
/// existing intent; rebuilding or switching tabs never creates a new read.
class ForumClipboardLinkHost extends ConsumerStatefulWidget {
  const ForumClipboardLinkHost({
    super.key,
    required this.isReady,
    this.allowPrompt = true,
    required this.builder,
  });

  final bool isReady;
  final bool allowPrompt;
  final WidgetBuilder builder;

  @override
  ConsumerState<ForumClipboardLinkHost> createState() =>
      _ForumClipboardLinkHostState();
}

class _ForumClipboardLinkHostState extends ConsumerState<ForumClipboardLinkHost>
    with WidgetsBindingObserver {
  late final ForumClipboardRuntime _runtime;
  late final ForumClipboardRouteObserver _routes;
  late final Object _host;
  final _navigation = ThreadPostNavigationSession();
  final _notice = ForumClipboardSnackBarPresenter();
  ModalRoute<dynamic>? _route;
  bool _focused = true;
  bool _backgrounded = false;
  bool _resumePending = false;
  bool _firstFrame = false;
  bool _rebuildScheduled = false;
  bool _noticeScheduled = false;
  int? _viewId;
  double _keyboardInset = 0;
  bool _authReady = false;

  @override
  void initState() {
    super.initState();
    _runtime = ref.read(forumClipboardRuntimeProvider);
    _routes = ref.read(forumClipboardRouteObserverProvider);
    _host = _runtime.attach();
    _runtime.addListener(_changed);
    _routes.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _firstFrame = true;
      _changed();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _viewId = View.of(context).viewId;
    _keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgrounded = true;
    }
    if (state != AppLifecycleState.resumed) {
      _runtime.coordinator.cancelOperations();
      _navigation.invalidate();
    } else if (_backgrounded) {
      _backgrounded = false;
      _resumePending = true;
    }
    _changed();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != _viewId) return;
    _focused = event.state == ViewFocusState.focused;
    if (!_focused) {
      _runtime.coordinator.cancelOperations();
      _navigation.invalidate();
    }
    _changed();
  }

  bool get _foreground {
    // Outer hosts may release their gates earlier in the same lifecycle
    // broadcast. The binding already holds the new state before callbacks.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  bool get _available =>
      _runtime.owns(_host) &&
      _firstFrame &&
      widget.isReady &&
      widget.allowPrompt &&
      _foreground &&
      _focused &&
      _keyboardInset == 0 &&
      _authReady &&
      _runtime.isUnblocked &&
      _route?.isCurrent != false &&
      !_routes.isTransitioning;

  void _sync() {
    if (!mounted || !_runtime.owns(_host)) return;
    final auth = ref.read(authSessionControllerProvider);
    final wasAuthReady = _authReady;
    _authReady = !auth.isLoading && auth.asData?.value.isLoggingOut == false;
    if (wasAuthReady && !_authReady) {
      _runtime.coordinator.cancelOperations();
      _navigation.invalidate();
    }
    final coldReady =
        _runtime.needsColdCheck &&
        _firstFrame &&
        widget.isReady &&
        _authReady &&
        _runtime.isUnblocked;
    final resumeReady = _resumePending;
    if (coldReady || resumeReady) {
      _resumePending = false;
      // Merge lifecycle opportunities before making the pending queue runnable.
      // Otherwise a resumed read can be started and immediately superseded.
      _runtime.updateEligibility(_host, available: false);
      if (coldReady) _runtime.requestColdCheck(_host);
      if (resumeReady) _runtime.coordinator.requestCheck();
    }
    _runtime.updateEligibility(_host, available: _available);
  }

  void _changed() {
    if (!mounted) return;
    _sync();
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_rebuildScheduled) return;
      _rebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _scheduleNotice() {
    if (_noticeScheduled) return;
    _noticeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noticeScheduled = false;
      if (!mounted) return;
      _sync();
      final candidate = _available ? _runtime.coordinator.candidate : null;
      _notice.show(
        context: context,
        candidate: candidate,
        isCurrent: () =>
            mounted &&
            _available &&
            identical(candidate, _runtime.coordinator.candidate),
        onOpen: () => _open(candidate!),
        onShown: () => _runtime.coordinator.markShown(candidate!),
        onDismiss: () {
          if (mounted && _runtime.owns(_host)) {
            _runtime.coordinator.dismiss(candidate!);
            _changed();
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionControllerProvider);
    ref.listen(authSessionControllerProvider, (_, _) => _changed());
    _sync();
    _scheduleNotice();
    return widget.builder(context);
  }

  void _open(ForumClipboardLinkCandidate candidate) {
    _sync();
    if (!_available || !_runtime.owns(_host)) return;
    final lease = _runtime.coordinator.takeForOpen(candidate);
    if (lease == null) return;
    unawaited(
      ref
          .read(forumLinkOpenerProvider)
          .open(
            context: context,
            url: candidate.url,
            session: _navigation,
            isCurrent: () =>
                mounted &&
                _runtime.owns(_host) &&
                lease() &&
                _foreground &&
                _focused &&
                _authReady,
            onCopyLink: (url) =>
                ref.read(clipboardTextWriterProvider).writeText(url),
          ),
    );
  }

  @override
  void dispose() {
    _notice.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _runtime.removeListener(_changed);
    _routes.removeListener(_changed);
    _runtime.detach(_host);
    _navigation.dispose();
    super.dispose();
  }
}
