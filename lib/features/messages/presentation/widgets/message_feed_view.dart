import 'package:flutter/material.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';

/// Each mounted view owns its activity independently of other feed consumers.
class MessageFeedView<P> extends StatefulWidget {
  const MessageFeedView({
    super.key,
    required this.controller,
    required this.builder,
    this.isActive = true,
  });

  final MessageFeedController<P> controller;
  final Widget Function(BuildContext, MessageFeedState<P>) builder;
  final bool isActive;

  @override
  State<MessageFeedView<P>> createState() => _MessageFeedViewState<P>();
}

class _MessageFeedViewState<P> extends State<MessageFeedView<P>> {
  final _owner = Object();

  void _syncActivity() {
    widget.controller.setActive(
      widget.isActive && (ModalRoute.isCurrentOf(context) ?? true),
      owner: _owner,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncActivity();
  }

  @override
  void didUpdateWidget(covariant MessageFeedView<P> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.setActive(false, owner: _owner);
    }
    _syncActivity();
  }

  @override
  void dispose() {
    widget.controller.setActive(false, owner: _owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.controller,
    builder: (context, state, _) => widget.builder(context, state),
  );
}
