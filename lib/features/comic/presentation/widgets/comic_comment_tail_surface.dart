import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_content_projection_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_card.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_list_surface.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_surface.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_surface.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_render_context.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Maps one comment session into the neutral reader tail contract.
///
/// The paged tail owns its own bounded list. The vertical tail contributes
/// individual lazy rows to the reader's existing ListView, so it never nests a
/// second scrollable list inside the image stream.
class ComicCommentTailSurface extends ChangeNotifier
    implements ReaderTailSurface {
  ComicCommentTailSurface({
    required ComicCommentSessionController session,
    required ComicCommentContentProjectionController
    contentProjectionController,
    required ImageRequestHeaderBuilder? imageHeaderBuilder,
    bool hasNextEpisode = false,
    FutureOr<void> Function()? onAdvanceEpisode,
  }) : _session = session,
       _contentProjectionController = contentProjectionController,
       _imageHeaderBuilder = imageHeaderBuilder,
       _hasNextEpisode = hasNextEpisode,
       _onAdvanceEpisode = onAdvanceEpisode {
    _session.addListener(_onSessionChanged);
    _contentProjectionController.addListener(_onProjectionChanged);
  }

  final ComicCommentSessionController _session;
  final ComicCommentContentProjectionController _contentProjectionController;
  final ImageRequestHeaderBuilder? _imageHeaderBuilder;
  bool _hasNextEpisode;
  FutureOr<void> Function()? _onAdvanceEpisode;

  void updateNavigation({
    required bool hasNextEpisode,
    required FutureOr<void> Function()? onAdvanceEpisode,
  }) {
    _hasNextEpisode = hasNextEpisode;
    _onAdvanceEpisode = onAdvanceEpisode;
  }

  ThreadPostRenderContext? _renderContext;
  Object? _renderContextIdentity;
  String? _prunedProjectionIdentity;
  bool _disposed = false;

  ComicCommentSessionState get sessionState => _session.state;

  @override
  String get id => 'comic-comments-${_session.key.id}';

  @override
  String indicatorLabel(BuildContext context) =>
      AppLocalizations.of(context).comicComment;

  @override
  bool get hasAdvance =>
      _hasNextEpisode && _onAdvanceEpisode != null && isAdjacentPreloadReady;

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
      return const ComicCommentFeedbackSurface(
        key: Key('comic-comment-tail-loading'),
        kind: ComicCommentFeedbackKind.loading,
      );
    }
    final list = ComicCommentListSurface(
      sourceTid: _session.key.sourceTid,
      projection: _projectionFor(result),
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
        const ComicCommentFeedbackSurface(
          kind: ComicCommentFeedbackKind.lastChapter,
          compact: true,
        ),
      ],
    );
  }

  @override
  Widget buildAdvance(BuildContext context, ReaderTailActions actions) {
    // This page exists only because PageView needs a real child to receive
    // the swipe after the comment page. It must never become reader chrome.
    return const ExcludeSemantics(
      child: SizedBox.expand(key: Key('comic-comment-tail-advance-sentinel')),
    );
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
    final projection = loadedResult == null
        ? null
        : _projectionFor(loadedResult);
    if (loadedResult != null &&
        projection != null &&
        (loadedResult.status == ComicCommentLoadStatus.success ||
            loadedResult.status == ComicCommentLoadStatus.partialFailure)) {
      if (index < projection.items.length) {
        final itemProjection = projection.items[index];
        return Padding(
          key: ValueKey<String>(
            'comic-comment-tail-item-${itemProjection.sourceItem.pid}',
          ),
          padding: EdgeInsets.fromLTRB(12, index == 0 ? 12 : 0, 12, 10),
          child: ComicCommentListItem(
            projection: itemProjection,
            sourceTid: _session.key.sourceTid,
            imageHeaderBuilder: _imageHeaderBuilder,
            renderContext: _renderContextFor(context),
          ),
        );
      }
      if (loadedResult.status == ComicCommentLoadStatus.partialFailure) {
        return ComicCommentFeedbackSurface(
          key: const Key('comic-comment-tail-partial-failure'),
          kind: ComicCommentFeedbackKind.unavailable,
          onAction: () => unawaited(_handleVerticalRequest(context)),
          compact: true,
        );
      }
      if (!_hasNextEpisode && index == projection.items.length) {
        return const ComicCommentFeedbackSurface(
          key: Key('comic-comment-tail-last-chapter'),
          kind: ComicCommentFeedbackKind.lastChapter,
          compact: true,
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
      return const ComicCommentFeedbackSurface(
        key: Key('comic-comment-tail-loading'),
        kind: ComicCommentFeedbackKind.loading,
      );
    }
    if (result == null) {
      return ComicCommentFeedbackSurface(
        actionKey: const Key('comic-comment-tail-load-button'),
        kind: ComicCommentFeedbackKind.open,
        onAction: () => unawaited(_handleVerticalRequest(context)),
      );
    }
    switch (result.status) {
      case ComicCommentLoadStatus.empty:
        return const ComicCommentFeedbackSurface(
          key: Key('comic-comment-tail-empty'),
          kind: ComicCommentFeedbackKind.empty,
        );
      case ComicCommentLoadStatus.failure:
      case ComicCommentLoadStatus.cancelled:
        return ComicCommentFeedbackSurface(
          key: const Key('comic-comment-tail-failure'),
          kind: ComicCommentFeedbackKind.unavailable,
          onAction: () => unawaited(_handleVerticalRequest(context)),
        );
      case ComicCommentLoadStatus.success:
        return const SizedBox.shrink();
      case ComicCommentLoadStatus.partialFailure:
        return result.items.isEmpty
            ? ComicCommentFeedbackSurface(
                key: const Key('comic-comment-tail-failure'),
                kind: ComicCommentFeedbackKind.unavailable,
                onAction: () => unawaited(_handleVerticalRequest(context)),
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
      showTransientSnackBar(
        context,
        AppLocalizations.of(context).comicCommentUnavailableFeedback,
      );
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
    if (result != null) {
      final projection = _projectionFor(result);
      if (_prunedProjectionIdentity != projection.displayIdentity) {
        _renderContext!.prune(
          projection.items.map(ComicCommentCard.toThreadPost),
        );
        _prunedProjectionIdentity = projection.displayIdentity;
      }
    }
    return _renderContext!;
  }

  ComicCommentContentProjection _projectionFor(ComicCommentLoadResult result) {
    return _contentProjectionController.projectionFor(result);
  }

  void _onSessionChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _onProjectionChanged() {
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
    _contentProjectionController.removeListener(_onProjectionChanged);
    super.dispose();
  }
}
