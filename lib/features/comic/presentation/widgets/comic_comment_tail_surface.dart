import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_list_surface.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_surface.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_render_context.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

/// Maps one comment session into the neutral reader tail contract.
///
/// The paged tail owns its own bounded list. The vertical tail contributes
/// individual lazy rows to the reader's existing ListView, so it never nests a
/// second scrollable list inside the image stream.
class ComicCommentTailSurface extends ChangeNotifier
    implements ReaderTailSurface {
  ComicCommentTailSurface({
    required ComicCommentSessionController session,
    required ImageRequestHeaderBuilder? imageHeaderBuilder,
  }) : _session = session,
       _imageHeaderBuilder = imageHeaderBuilder {
    _session.addListener(_onSessionChanged);
  }

  final ComicCommentSessionController _session;
  final ImageRequestHeaderBuilder? _imageHeaderBuilder;
  ThreadPostRenderContext? _renderContext;
  Object? _renderContextIdentity;
  bool _disposed = false;

  ComicCommentSessionState get sessionState => _session.state;

  @override
  String get id => 'comic-comments-${_session.key.id}';

  @override
  String get indicatorLabel => '评论';

  @override
  bool get hasAdvance => false;

  @override
  int get verticalItemCount {
    final state = sessionState;
    final result = state.result;
    if (state.isLoading || result == null) {
      return 1;
    }
    if (result.status == ComicCommentLoadStatus.success &&
        result.items.isNotEmpty) {
      return result.items.length;
    }
    if (result.status == ComicCommentLoadStatus.partialFailure &&
        result.items.isNotEmpty) {
      return result.items.length + 1;
    }
    return 1;
  }

  @override
  Widget buildPaged(BuildContext context, ReaderTailActions actions) {
    final state = sessionState;
    final result = state.result;
    if (state.isLoading || result == null) {
      return const _CommentTailLoading();
    }
    return ComicCommentListSurface(
      sourceTid: _session.key.sourceTid,
      result: result,
      imageHeaderBuilder: _imageHeaderBuilder,
      onRetry: actions.onRetry,
      renderContext: _renderContextFor(context),
    );
  }

  @override
  Widget buildAdvance(BuildContext context, ReaderTailActions actions) {
    return const SizedBox.shrink();
  }

  @override
  Widget buildVertical(BuildContext context, ReaderTailActions actions) {
    return buildVerticalItem(context, actions, 0);
  }

  @override
  Widget buildVerticalItem(
    BuildContext context,
    ReaderTailActions actions,
    int index,
  ) {
    final state = sessionState;
    final result = state.result;
    if (result != null &&
        (result.status == ComicCommentLoadStatus.success ||
            result.status == ComicCommentLoadStatus.partialFailure)) {
      if (index < result.items.length) {
        return Padding(
          key: ValueKey<String>(
            'comic-comment-tail-item-${result.items[index].pid}',
          ),
          padding: EdgeInsets.fromLTRB(12, index == 0 ? 12 : 0, 12, 10),
          child: ComicCommentListItem(
            comment: result.items[index],
            sourceTid: _session.key.sourceTid,
            imageHeaderBuilder: _imageHeaderBuilder,
            renderContext: _renderContextFor(context),
          ),
        );
      }
      return _CommentTailFailure(
        key: const Key('comic-comment-tail-partial-failure'),
        message: result.errorMessage,
        onRetry: () => unawaited(_handleVerticalRequest(context)),
        compact: true,
      );
    }
    return _buildStatus(context, state, result);
  }

  @override
  Future<void> onVisible() => _session.load();

  @override
  Future<void> onVerticalVisible() async {}

  @override
  Future<void> onRetry() =>
      _session.state.result == null ? _session.load() : _session.retry();

  @override
  Future<void> onAdvance() async {}

  Widget _buildStatus(
    BuildContext context,
    ComicCommentSessionState state,
    ComicCommentLoadResult? result,
  ) {
    if (state.isLoading) {
      return const _CommentTailLoading();
    }
    if (result == null) {
      return _CommentTailAction(
        title: '查看评论',
        onPressed: () => unawaited(_handleVerticalRequest(context)),
      );
    }
    switch (result.status) {
      case ComicCommentLoadStatus.empty:
        return const _CommentTailEmpty();
      case ComicCommentLoadStatus.failure:
      case ComicCommentLoadStatus.cancelled:
        return _CommentTailFailure(
          message: result.errorMessage,
          onRetry: () => unawaited(_handleVerticalRequest(context)),
        );
      case ComicCommentLoadStatus.success:
        return const SizedBox.shrink();
      case ComicCommentLoadStatus.partialFailure:
        return result.items.isEmpty
            ? _CommentTailFailure(
                message: result.errorMessage,
                onRetry: () => unawaited(_handleVerticalRequest(context)),
              )
            : const SizedBox.shrink();
    }
  }

  Future<void> _handleVerticalRequest(BuildContext context) async {
    final result = sessionState.result;
    if (sessionState.isLoading) {
      return;
    }
    if (result == null) {
      await _session.load();
    } else {
      await _session.retry();
    }
    final next = sessionState.result;
    if (!context.mounted || next == null) {
      return;
    }
    if (next.status == ComicCommentLoadStatus.failure ||
        next.status == ComicCommentLoadStatus.cancelled) {
      showTransientSnackBar(context, '无法查看评论');
    }
  }

  ThreadPostRenderContext _renderContextFor(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final identity = (
      sourceTid: _session.key.sourceTid.trim(),
      imageHeaderBuilder: _imageHeaderBuilder,
      brightness: Theme.of(context).brightness,
      palette: palette.card.toARGB32(),
    );
    if (_renderContextIdentity != identity || _renderContext == null) {
      _renderContextIdentity = identity;
      _renderContext = ThreadPostRenderContext(
        palette: palette,
        imageHeaderBuilder: _imageHeaderBuilder,
        renderOwnerFor: (post) => ThreadPostRenderContext.commentRenderOwner(
          sourceTid: _session.key.sourceTid,
          pid: post.pid,
        ),
      );
    }
    return _renderContext!;
  }

  void _onSessionChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }
}

class _CommentTailAction extends StatelessWidget {
  const _CommentTailAction({required this.title, required this.onPressed});

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 56),
      child: Center(
        child: OutlinedButton.icon(
          key: const Key('comic-comment-tail-load-button'),
          onPressed: onPressed,
          icon: const Icon(Icons.forum_outlined),
          label: Text(title),
        ),
      ),
    );
  }
}

class _CommentTailLoading extends StatelessWidget {
  const _CommentTailLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('comic-comment-tail-loading'),
      padding: EdgeInsets.all(28),
      child: Center(child: Text('评论加载中')),
    );
  }
}

class _CommentTailEmpty extends StatelessWidget {
  const _CommentTailEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('comic-comment-tail-empty'),
      padding: EdgeInsets.fromLTRB(20, 28, 20, 56),
      child: Center(child: Text('暂无评论')),
    );
  }
}

class _CommentTailFailure extends StatelessWidget {
  const _CommentTailFailure({
    super.key,
    this.message,
    required this.onRetry,
    this.compact = false,
  });

  final String? message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 6 : 28, 20, compact ? 10 : 56),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(message ?? '评论暂不可用')),
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
