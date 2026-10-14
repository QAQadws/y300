part of 'thread_detail_widgets.dart';

Widget _chunkRenderer(
  ThreadDetailBodyManifest manifest,
  ThreadDetailPreparedChunk chunk, {
  required ForumHtmlReaderPreferences preferences,
  ForumHtmlRenderCallbacks callbacks = const ForumHtmlRenderCallbacks(),
  VoidCallback? onBodyBuilt,
}) {
  final request = manifest.request;
  return ForumHtmlWidgetPostRenderer(
    html: chunk.html,
    theme: request.theme,
    preferences: preferences,
    preparedDocument: chunk.document,
    sourceId: request.sourceId,
    threadId: request.threadId,
    hasTrailingContent: chunk.hasTrailingContent,
    callbacks: callbacks,
    onBodyBuilt: onBodyBuilt,
  );
}

/// A mounted consumer retains its own chunk, never the prepared whole body.
class _ThreadPostChunkBody extends ConsumerStatefulWidget {
  const _ThreadPostChunkBody({
    required this.manifest,
    required this.preparation,
    required this.store,
    required this.layoutIdentity,
    required this.ordinal,
    required this.post,
    required this.sourcePost,
    required this.theme,
    required this.onPreparedBody,
    this.preparerSelector,
    required this.onOpenPostLink,
  });

  final ThreadDetailBodyManifest manifest;
  final ThreadBodyChunkPreparation preparation;
  final ThreadDetailPreparedBodyStore store;
  final Object layoutIdentity;
  final int ordinal;
  final ThreadPost post;
  final ThreadPost sourcePost;
  final ForumHtmlThemeContext theme;
  final ThreadPreparedBodyHandoff onPreparedBody;
  final ThreadPreparedBodyPreparerSelector? preparerSelector;
  final ValueChanged<String> onOpenPostLink;

  @override
  ConsumerState<_ThreadPostChunkBody> createState() =>
      _ThreadPostChunkBodyState();
}

class _ThreadPostChunkBodyState extends ConsumerState<_ThreadPostChunkBody> {
  final _key = GlobalKey();
  final _demandOwner = Object();
  final _preparation = ForumHtmlPreparationController();
  ThreadDetailPreparedChunk? _chunk;
  Object? _chunkIdentity;
  double? _lastActualHeight;
  bool _bodyHasBuilt = false;

  @override
  void initState() {
    super.initState();
    _preparation.addListener(_changed);
    widget.preparation.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _ThreadPostChunkBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.preparation, widget.preparation)) {
      oldWidget.preparation.removeListener(_changed);
      oldWidget.preparation.release(_demandOwner);
      widget.preparation.addListener(_changed);
    }
    if (!identical(oldWidget.manifest, widget.manifest) ||
        oldWidget.ordinal != widget.ordinal) {
      _chunk = null;
      _chunkIdentity = null;
      _bodyHasBuilt = false;
      widget.preparation.release(_demandOwner);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _preparation.dispose();
    widget.preparation.removeListener(_changed);
    widget.preparation.release(_demandOwner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences =
        ref.watch(forumHtmlReaderPreferencesControllerProvider).value ??
        ForumHtmlReaderPreferences.defaults();
    final baseRequest = ForumHtmlPreparationRequest(
      html: widget.post.message.trim(),
      preferences: preferences,
      theme: widget.theme,
      sourceId: widget.sourcePost.pid,
      threadId: widget.manifest.request.threadId,
      imageCacheOwnerId: widget.manifest.request.imageCacheOwnerId,
      preparer: const DefaultForumHtmlRenderPreparer(
        enablePlainTextLinks: true,
        enableSafeDisplayPlanning: true,
      ),
    );
    final selected = widget.preparerSelector?.call(baseRequest);
    final request =
        selected == null || identical(selected, baseRequest.preparer)
        ? baseRequest
        : baseRequest.withPreparer(selected);
    widget.store.activateHeightLayout(
      widget.manifest,
      layoutIdentity: widget.layoutIdentity,
    );
    final height = widget.store.heightFor(
      widget.manifest,
      widget.ordinal,
      layoutIdentity: widget.layoutIdentity,
    );
    // Unknown heights are waiting space, not measured reading geometry. One
    // viewport avoids demanding dozens of 48-line chunks as tiny placeholders.
    final pendingHeight = height ?? MediaQuery.sizeOf(context).height;
    if (request.identity != widget.manifest.identity) {
      widget.preparation.release(_demandOwner);
      _chunk = null;
      _chunkIdentity = null;
      _bodyHasBuilt = false;
      ForumHtmlPreparedRenderDocument? document;
      try {
        document = _preparation.resolve(request);
      } catch (_) {
        // The whole-body owner supplies the existing error/retry presentation.
        // Retire the stale manifest through the existing whole-body error path.
        // Cache misses for an unchanged manifest use the retry block below.
        document = _emptyFailedDocument(request);
      }
      if (document != null) widget.onPreparedBody(context, request, document);
      // Keep the last actual chunk height while its replacement is prepared.
      return SizedBox(
        height: _lastActualHeight ?? pendingHeight,
        child: const ForumHtmlPreparationPlaceholder(),
      );
    }
    _preparation.reset();
    try {
      if (_chunkIdentity != widget.manifest.identity) _chunk = null;
      _chunk ??= widget.preparation.resolve(
        _demandOwner,
        widget.manifest,
        widget.ordinal,
      );
      if (_chunk == null) {
        return SizedBox(
          height: pendingHeight,
          child: const ForumHtmlPreparationPlaceholder(),
        );
      }
    } catch (_) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: pendingHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ThreadPostHtmlBodyError(),
            TextButton(
              onPressed: () => widget.preparation.retry(widget.manifest),
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      );
    }
    _chunkIdentity = widget.manifest.identity;
    widget.preparation.release(_demandOwner);
    _recordActualHeight();
    final manifest = widget.manifest;
    final ordinal = widget.ordinal;
    final layout = widget.layoutIdentity;
    return KeyedSubtree(
      key: _key,
      child: KeyedSubtree(
        key: Key('thread-post-html-first-body-${request.sourceId}'),
        child: _chunkRenderer(
          widget.manifest,
          _chunk!,
          preferences: preferences,
          onBodyBuilt: () {
            if (!mounted ||
                !identical(manifest, widget.manifest) ||
                ordinal != widget.ordinal ||
                layout != widget.layoutIdentity ||
                _chunkIdentity != manifest.identity) {
              return;
            }
            _bodyHasBuilt = true;
            _recordActualHeight();
          },
          callbacks: ForumHtmlRenderCallbacks(
            onTapUrl: (url) {
              widget.onOpenPostLink(url);
              return true;
            },
          ),
        ),
      ),
    );
  }

  void _recordActualHeight() {
    if (!_bodyHasBuilt) return;
    final manifest = widget.manifest;
    final ordinal = widget.ordinal;
    final layout = widget.layoutIdentity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(manifest, widget.manifest) ||
          ordinal != widget.ordinal ||
          layout != widget.layoutIdentity ||
          _chunkIdentity != manifest.identity) {
        return;
      }
      final box = _key.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          box.size.height > 0) {
        _lastActualHeight = box.size.height;
        widget.store.rememberHeight(
          manifest,
          ordinal,
          layoutIdentity: layout,
          height: box.size.height,
        );
      }
    });
  }
}

ForumHtmlPreparedRenderDocument _emptyFailedDocument(
  ForumHtmlPreparationRequest request,
) => ForumHtmlPreparedRenderDocument(
  preparedHtml: request.html,
  sequence: ForumHtmlReadableImageSequence(
    sourceId: request.sourceId,
    entries: const [],
  ),
  attachmentIdsByUrl: const {},
  totalImageCount: 0,
  skippedStickerCount: 0,
  skippedNonNetworkCount: 0,
  duplicatedReadableUrlCount: 0,
  attachmentTaggedCount: 0,
  themeSignature: request.theme.signature,
  themeAdaptationStats: ForumHtmlThemeAdaptationStats.none,
);
