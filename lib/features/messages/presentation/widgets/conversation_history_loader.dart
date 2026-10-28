import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';
import 'package:y300/features/messages/presentation/widgets/message_read_status.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Keeps one history demand per user scroll, including while a read is busy.
class ConversationHistoryLoader extends StatefulWidget {
  const ConversationHistoryLoader({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.child,
  });

  final MessageFeedController<ForumPrivateMessagePage> controller;
  final ScrollController scrollController;
  final Widget child;

  @override
  State<ConversationHistoryLoader> createState() =>
      _ConversationHistoryLoaderState();
}

class _ConversationHistoryLoaderState extends State<ConversationHistoryLoader>
    with WidgetsBindingObserver {
  static const _historyThreshold = 160;
  bool _userScrolling = false;
  bool _attempted = false;
  bool _pending = false;
  bool _scheduled = false;

  bool get _isVisible {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return ModalRoute.isCurrentOf(context) != false &&
        TickerMode.valuesOf(context).enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFeedChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ConversationHistoryLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onFeedChanged);
      widget.controller.addListener(_onFeedChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.scrollController != widget.scrollController) {
      _pending = false;
      _userScrolling = false;
      _attempted = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isVisible) _pending = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pending = false;
  }

  void _onFeedChanged() {
    if (!widget.controller.hasMore || widget.controller.value.failure != null) {
      _pending = false;
    }
    _schedulePending();
  }

  void _schedulePending() {
    if (!_pending || _scheduled || widget.controller.value.isBusy) return;
    _scheduled = true;
    // A completed read may extend history. Check its final layout before
    // satisfying the demand; layout changes alone never create another one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_pending) return;
      final controller = widget.controller;
      if (!_isVisible ||
          !controller.hasMore ||
          controller.value.failure != null ||
          !widget.scrollController.hasClients) {
        _pending = false;
        return;
      }
      final position = widget.scrollController.position;
      if (!position.hasContentDimensions ||
          position.maxScrollExtent - position.pixels > _historyThreshold) {
        _pending = false;
        return;
      }
      if (controller.value.isBusy) return;
      _pending = false;
      _attempted = true;
      unawaited(controller.loadMore());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _requestHistory(ScrollMetrics metrics) {
    if (_attempted ||
        !widget.controller.hasMore ||
        widget.controller.value.failure != null ||
        metrics.maxScrollExtent - metrics.pixels > _historyThreshold) {
      return;
    }
    _pending = true;
    _schedulePending();
  }

  bool _onScroll(ScrollNotification notification) {
    // Tables/code can scroll inside a message; only the conversation counts.
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails == null) {
      _pending = false;
      _userScrolling = false;
    }
    if (notification is UserScrollNotification) {
      final active = notification.direction != ScrollDirection.idle;
      if (active && !_userScrolling) _attempted = false;
      _userScrolling = active;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (_userScrolling && delta > 0) {
        _requestHistory(notification.metrics);
      } else if (delta < 0 || !_userScrolling) {
        _pending = false;
      }
    }
    if (notification is OverscrollNotification) {
      if (_userScrolling && notification.overscroll > 0) {
        _requestHistory(notification.metrics);
      } else if (notification.overscroll < 0) {
        _pending = false;
      }
    }
    return false;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFeedChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );
}

class ConversationHistoryEntry extends StatelessWidget {
  const ConversationHistoryEntry({super.key, required this.controller});

  final MessageFeedController<ForumPrivateMessagePage> controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.value;
    final failure = state.failedOperation == MessageFeedOperation.more
        ? state.failure
        : null;
    if (failure != null) {
      return MessageReadStatus(
        failure: failure,
        onRetry: failure.code == 'message_history_changed'
            ? controller.refresh
            : controller.loadMore,
      );
    }
    final l10n = AppLocalizations.of(context);
    final loading = state.operation == MessageFeedOperation.more;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        // Keep the button's footprint: shrinking this row at the scroll edge
        // would clamp the offset and move the messages while the read is busy.
        child: Stack(
          alignment: Alignment.center,
          children: [
            Visibility(
              visible: !loading,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: TextButton(
                onPressed: state.isBusy ? null : controller.loadMore,
                child: Text(l10n.messageOlder),
              ),
            ),
            if (loading)
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: l10n.messageOlder,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
