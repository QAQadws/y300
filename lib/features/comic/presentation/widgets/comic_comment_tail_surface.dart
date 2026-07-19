import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_card.dart';
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
    bool hasNextEpisode = false,
    String? nextEpisodeTitle,
    FutureOr<void> Function()? onAdvanceEpisode,
  }) : _session = session,
       _imageHeaderBuilder = imageHeaderBuilder,
       _hasNextEpisode = hasNextEpisode,
       _nextEpisodeTitle = nextEpisodeTitle,
       _onAdvanceEpisode = onAdvanceEpisode {
    _session.addListener(_onSessionChanged);
  }

  final ComicCommentSessionController _session;
  final ImageRequestHeaderBuilder? _imageHeaderBuilder;
  bool _hasNextEpisode;
  String? _nextEpisodeTitle;
  FutureOr<void> Function()? _onAdvanceEpisode;

  void updateNavigation({
    required bool hasNextEpisode,
    required String? nextEpisodeTitle,
    required FutureOr<void> Function()? onAdvanceEpisode,
  }) {
    _hasNextEpisode = hasNextEpisode;
    _nextEpisodeTitle = nextEpisodeTitle;
    _onAdvanceEpisode = onAdvanceEpisode;
  }

  ThreadPostRenderContext? _renderContext;
  Object? _renderContextIdentity;
  Object? _prunedResult;
  bool _disposed = false;

  ComicCommentSessionState get sessionState => _session.state;

  @override
  String get id => 'comic-comments-${_session.key.id}';

  @override
  String get indicatorLabel => '评论';

  @override
  bool get hasAdvance => _hasNextEpisode && _onAdvanceEpisode != null;

  @override
  bool get isAdjacentPreloadReady {
    final status = sessionState.result?.status;
    return status == ComicCommentLoadStatus.success ||
        status == ComicCommentLoadStatus.empty ||
        status == ComicCommentLoadStatus.partialFailure;
  }

  @override
  int get verticalItemCount {
    final state = sessionState;
    final result = state.result;
    if (state.isLoading || result == null) {
      return 1;
    }
    if (result.status == ComicCommentLoadStatus.success &&
        result.items.isNotEmpty) {
      return result.items.length + (_hasNextEpisode ? 0 : 1);
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
    final list = ComicCommentListSurface(
      sourceTid: _session.key.sourceTid,
      result: result,
      imageHeaderBuilder: _imageHeaderBuilder,
      onRetry: actions.onRetry,
      renderContext: _renderContextFor(context),
    );
    if (_hasNextEpisode) {
      return list;
    }
    return Column(
      children: [
        Expanded(child: list),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Text('已是最后一章'),
        ),
      ],
    );
  }

  @override
  Widget buildAdvance(BuildContext context, ReaderTailActions actions) {
    return _CommentAdvance(nextEpisodeTitle: _nextEpisodeTitle);
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
    final loadedResult = result;
    if (loadedResult != null &&
        (loadedResult.status == ComicCommentLoadStatus.success ||
            loadedResult.status == ComicCommentLoadStatus.partialFailure)) {
      if (index < loadedResult.items.length) {
        return Padding(
          key: ValueKey<String>(
            'comic-comment-tail-item-${loadedResult.items[index].pid}',
          ),
          padding: EdgeInsets.fromLTRB(12, index == 0 ? 12 : 0, 12, 10),
          child: ComicCommentListItem(
            comment: loadedResult.items[index],
            sourceTid: _session.key.sourceTid,
            imageHeaderBuilder: _imageHeaderBuilder,
            renderContext: _renderContextFor(context),
          ),
        );
      }
      if (loadedResult.status == ComicCommentLoadStatus.partialFailure) {
        return _CommentTailFailure(
          key: const Key('comic-comment-tail-partial-failure'),
          message: loadedResult.errorMessage,
          onRetry: () => unawaited(_handleVerticalRequest(context)),
          compact: true,
        );
      }
      if (!_hasNextEpisode && index == loadedResult.items.length) {
        return const _CommentLastChapter(
          key: Key('comic-comment-tail-last-chapter'),
        );
      }
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
  Future<void> onAdvance() async {
    final callback = _onAdvanceEpisode;
    if (callback != null) {
      await callback();
    }
  }

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
    final result = sessionState.result;
    if (result != null && !identical(_prunedResult, result)) {
      _renderContext!.prune(result.items.map(ComicCommentCard.toThreadPost));
      _prunedResult = result;
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

class _CommentAdvance extends StatelessWidget {
  const _CommentAdvance({this.nextEpisodeTitle});

  final String? nextEpisodeTitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('comic-comment-tail-advance'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swipe_outlined),
            const SizedBox(height: 12),
            Text(
              nextEpisodeTitle == null || nextEpisodeTitle!.trim().isEmpty
                  ? '继续滑动进入下一章'
                  : '继续滑动进入：$nextEpisodeTitle',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentLastChapter extends StatelessWidget {
  const _CommentLastChapter({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Center(child: Text('已是最后一章')),
    );
  }
}
