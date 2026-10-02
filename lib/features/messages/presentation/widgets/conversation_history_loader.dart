import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';
import 'package:y300/features/messages/presentation/widgets/message_read_status.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Loads at most one older page per user scroll, never from layout changes.
class ConversationHistoryLoader extends StatefulWidget {
  const ConversationHistoryLoader({
    super.key,
    required this.controller,
    required this.child,
  });

  final MessageFeedController<ForumPrivateMessagePage> controller;
  final Widget child;

  @override
  State<ConversationHistoryLoader> createState() =>
      _ConversationHistoryLoaderState();
}

class _ConversationHistoryLoaderState extends State<ConversationHistoryLoader> {
  bool _userScrolling = false;
  bool _attempted = false;

  bool _canLoad(MessageFeedController<ForumPrivateMessagePage> controller) =>
      controller.hasMore &&
      !controller.value.isBusy &&
      controller.value.failure == null;

  bool _onScroll(ScrollNotification notification) {
    // Tables/code can scroll inside a message; only the conversation counts.
    if (notification.depth != 0) return false;
    if (notification is UserScrollNotification) {
      final active = notification.direction != ScrollDirection.idle;
      if (active && !_userScrolling) _attempted = false;
      _userScrolling = active;
    }
    if (notification is ScrollUpdateNotification &&
        _userScrolling &&
        !_attempted &&
        (notification.scrollDelta ?? 0) > 0 &&
        notification.metrics.maxScrollExtent - notification.metrics.pixels <=
            160 &&
        _canLoad(widget.controller)) {
      _attempted = true;
      final controller = widget.controller;
      // Feed notifications rebuild the page; defer beyond scroll/layout work.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(widget.controller, controller) &&
            _canLoad(controller)) {
          controller.loadMore();
        }
      });
    }
    return false;
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: state.operation == MessageFeedOperation.more
            ? SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: l10n.messageOlder,
                ),
              )
            : TextButton(
                onPressed: state.isBusy ? null : controller.loadMore,
                child: Text(l10n.messageOlder),
              ),
      ),
    );
  }
}
