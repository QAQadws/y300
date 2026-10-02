import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/presentation/comic_comment_presentation_store.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_interaction_controller.dart';
import 'package:y300/features/thread/presentation/services/thread_post_actions.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/presentation/thread_post_text_slots.dart';
import 'package:flutter/material.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    hide ThreadPostRatingsRepository;
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_render_context.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

/// A full source post rendered through the shared native post surface.
class ComicCommentCard extends ConsumerStatefulWidget {
  const ComicCommentCard({
    super.key,
    required this.projection,
    required this.sourceTid,
    this.imageReferer,
    this.renderContext,
    this.interactionController,
    this.presentation,
  });

  final ComicCommentInteractionController? interactionController;
  final ComicCommentItemProjection projection;
  final String sourceTid;
  final String? imageReferer;
  final ThreadPostRenderContext? renderContext;
  final ComicCommentPostPresentation? presentation;

  /// Converts a comment to the existing parser-mode post-card input.
  ///
  /// Keeping this adapter public lets list surfaces prune the shared render
  /// plan cache without duplicating the post mapping rules.
  static ThreadPost toThreadPost(ComicCommentItemProjection projection) =>
      projection.renderPost;

  @override
  ConsumerState<ComicCommentCard> createState() => _ComicCommentCardState();
}

class _ComicCommentCardState extends ConsumerState<ComicCommentCard> {
  ThreadPostRenderContext? _ownedRenderContext;
  Object? _ownedRenderContextIdentity;

  late ComicCommentPostPresentation _presentation;

  @override
  void initState() {
    super.initState();
    _bindPresentation();
  }

  void _bindPresentation() {
    _presentation = widget.presentation ?? ComicCommentPostPresentation();
    _presentation.addListener(_onPresentationChanged);
    _convertRatings();
  }

  void _onPresentationChanged() {
    if (mounted) {
      setState(() {});
      _convertRatings();
    }
  }

  @override
  void didUpdateWidget(covariant ComicCommentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presentation, widget.presentation) ||
        (widget.presentation == null &&
            !identical(
              oldWidget.projection.sourceItem.sourcePost,
              widget.projection.sourceItem.sourcePost,
            ))) {
      _presentation.removeListener(_onPresentationChanged);
      if (oldWidget.presentation == null) _presentation.dispose();
      _bindPresentation();
    }
  }

  @override
  void dispose() {
    _presentation.removeListener(_onPresentationChanged);
    if (widget.presentation == null) _presentation.dispose();
    super.dispose();
  }

  Future<void> _openActions(
    ThreadPostActions actions,
    ThreadPostRenderContext renderContext,
  ) async {
    ThreadPostMutation? mutation;
    final source = widget.projection.sourceItem;
    await widget.interactionController?.perform(
      invoke: (_, current) async {
        mutation = await actions.show(
          sourcePost: source.post,
          displayPost: widget.projection.displayPost,
          // Copy/selection use the complete converted body, including images
          // omitted only from the reader's comment surface.
          plan: renderContext.planFor(widget.projection.displayPost),
        );
        return mutation != null;
      },
      refreshPage: () =>
          mutation == ThreadPostMutation.reply ? null : source.sourcePage,
    );
  }

  Future<void> _loadRatings() async {
    final url = widget.projection.sourceItem.post.ratingSummary?.viewAllUrl;
    if (url == null) return;
    final repository = ref.read(threadPostRatingsRepositoryProvider);
    await _presentation.loadRatings(() => repository.loadAll(url));
  }

  Future<void> _convertRatings() async {
    if (_presentation.ratings.details == null) return;
    final mode = ref.read(appServerContentConversionModeProvider);
    final converter = ref.read(textConverterProvider(mode));
    final service = ref.read(plainTextBatchConversionServiceProvider);
    await _presentation.convertRatings(
      identity: (mode, converter.id),
      convert: (details) async {
        final collector = ThreadPlainTextCollector();
        final slots = ThreadRatingDetailsTextSlots.collect(details, collector);
        final values = await service.convertAll(
          sources: collector.sources,
          converter: converter,
        );
        return slots.build(details, values);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _postForComment();
    final renderContext = widget.renderContext ?? _ensureRenderContext(context);
    final controller = widget.interactionController;
    final source = widget.projection.sourceItem;
    final read = controller?.session.state.result?.reads[source.sourcePage];
    final ownerGeneration = controller?.session.generation;
    bool current() =>
        mounted &&
        controller != null &&
        controller.session.isCurrent(ownerGeneration!);
    final actions = read == null
        ? null
        : ThreadPostActions(
            context: context,
            ref: ref,
            target: ThreadPostActionContext(
              tid: widget.sourceTid,
              fid: read.data.fid,
              subject: read.data.subject,
              page: source.sourcePage,
              capabilities: read.capabilities,
              sourceUri: Uri.tryParse(read.data.desktopUrl ?? ''),
            ),
            isCurrent: current,
            imageReferer: widget.imageReferer,
          );
    ref.listen(appServerContentConversionModeProvider, (_, next) {
      _convertRatings();
    });
    return ThreadPostCard(
      key: Key('comic-comment-card-${widget.projection.sourceItem.pid}'),
      post: post,
      state: null,
      imageReferer: widget.imageReferer,
      palette: ThreadDetailNativePalette.resolve(Theme.of(context)),
      ratingsViewState: _presentation.displayRatings,
      ratingsExpanded: _presentation.ratingsExpanded,
      onRatingsExpansionChanged: (value) => setState(() {
        _presentation.ratingsExpanded = value;
      }),
      commentsExpanded: _presentation.commentsExpanded,
      onCommentsExpansionChanged: (value) => setState(() {
        _presentation.commentsExpanded = value;
      }),
      onOpenAuthorProfile: actions?.navigation.openAuthor,
      onOpenCommentAuthorProfile: actions?.navigation.openCommentAuthor,
      onOpenPostLink: actions?.navigation.openLink,
      onOpenPostImages: actions?.navigation.openImages,
      onCopyActionUrl: actions?.navigation.copyUrl,
      onLoadAllRatings:
          read?.capabilities.supports(ThreadDetailCapability.ratingSummary) ==
              true
          ? (_) => _loadRatings()
          : null,
      onOpenPostActions: actions == null
          ? null
          : (_, _) => _openActions(actions, renderContext),
      avatarFallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
      renderContext: renderContext,
    );
  }

  ThreadPost _postForComment() =>
      ComicCommentCard.toThreadPost(widget.projection);

  ThreadPostRenderContext _ensureRenderContext(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final identity = (
      sourceTid: widget.sourceTid.trim(),
      imageReferer: widget.imageReferer,
      brightness: Theme.of(context).brightness,
      palette: palette.card.toARGB32(),
    );
    if (_ownedRenderContextIdentity != identity ||
        _ownedRenderContext == null) {
      _ownedRenderContextIdentity = identity;
      _ownedRenderContext = ThreadPostRenderContext(
        palette: palette,
        imageReferer: widget.imageReferer,
        bodyPresentationFor: (_) => _presentation.body,
        imageFallbackAspectRatioFor: (_, _, request) =>
            _presentation.imageAspectRatio(request.cacheKey),
        onBlockImageResolved: (_, _, request, size) =>
            _presentation.recordImageSize(request.cacheKey, size),
        renderOwnerFor: (post) => ThreadPostRenderContext.commentRenderOwner(
          sourceTid: widget.sourceTid,
          pid: post.pid,
        ),
      );
    }
    return _ownedRenderContext!;
  }
}
