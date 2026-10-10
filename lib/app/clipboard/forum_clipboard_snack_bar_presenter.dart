import 'dart:async';

import 'package:flutter/material.dart';

import 'forum_clipboard_link_notice.dart';
import 'forum_clipboard_link_policy.dart';

/// Uses the existing feedback queue without replacing a business SnackBar.
final class ForumClipboardSnackBarPresenter {
  _Presentation? _current;

  void show({
    required BuildContext context,
    required ForumClipboardLinkCandidate? candidate,
    required bool Function() isCurrent,
    required VoidCallback onOpen,
    required VoidCallback onShown,
    required VoidCallback onDismiss,
  }) {
    final current = _current;
    if (current != null) {
      if (identical(current.candidate, candidate) && !current.retired) return;
      current.retire();
      // Keep one queue entry while a retired optional prompt waits behind
      // business feedback. Its completion lets the host present fresh state.
      if (!current.closed) return;
      _current = null;
    }
    if (candidate == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final presentation = _Presentation(
      candidate: candidate,
      messenger: messenger,
      isCurrent: isCurrent,
    );
    _current = presentation;
    final controller = messenger.showSnackBar(
      buildForumClipboardLinkSnackBar(
        context: context,
        kind: candidate.kind,
        contentWrapper: (child) => _ScopedContent(
          key: ObjectKey(presentation),
          presentation: presentation,
          child: child,
        ),
        onVisible: () {
          if (presentation.isCurrent()) {
            onShown();
          } else {
            presentation.retire();
          }
        },
        onOpen: () {
          if (!presentation.isCurrent()) return;
          // SnackBarAction closes itself after this callback. Removing it here
          // would advance the queue and let the SDK close the next message.
          presentation.opening = true;
          onOpen();
        },
      ),
    );
    controller.closed.then((_) {
      presentation.closed = true;
      if (identical(_current, presentation)) {
        _current = null;
        onDismiss();
      }
    });
  }

  void dispose() {
    _current?.retire();
    _current = null;
  }
}

final class _Presentation {
  _Presentation({
    required this.candidate,
    required this.messenger,
    required bool Function() isCurrent,
  }) : _isCurrent = isCurrent;

  final ForumClipboardLinkCandidate candidate;
  final ScaffoldMessengerState messenger;
  final bool Function() _isCurrent;
  bool retired = false;
  bool closed = false;
  bool opening = false;
  int attachedCount = 0;
  bool _removalScheduled = false;

  bool isCurrent() => !retired && !closed && _isCurrent();

  void retire() {
    retired = true;
    removeWhenAttached();
  }

  void removeWhenAttached() {
    if (attachedCount == 0 || closed || opening || _removalScheduled) return;
    _removalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The public queue cannot remove an arbitrary queued message. Its
      // content only attaches at the front. Drain completion microtasks from
      // every post-frame callback before checking identity: another callback
      // may already have advanced the queue while the old content still mounts.
      scheduleMicrotask(
        () => scheduleMicrotask(() {
          _removalScheduled = false;
          if (attachedCount > 0 && !closed && !opening && messenger.mounted) {
            messenger.removeCurrentSnackBar();
          }
        }),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

class _ScopedContent extends StatefulWidget {
  const _ScopedContent({
    super.key,
    required this.presentation,
    required this.child,
  });

  final _Presentation presentation;
  final Widget child;

  @override
  State<_ScopedContent> createState() => _ScopedContentState();
}

class _ScopedContentState extends State<_ScopedContent> {
  @override
  void initState() {
    super.initState();
    widget.presentation.attachedCount++;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.presentation.isCurrent()) return widget.child;
    widget.presentation.removeWhenAttached();
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    widget.presentation.attachedCount--;
    super.dispose();
  }
}
