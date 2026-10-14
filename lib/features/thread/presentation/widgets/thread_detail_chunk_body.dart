part of 'thread_detail_widgets.dart';

Widget _chunkRenderer(
  ThreadDetailPreparedBody preparedBody,
  int ordinal, {
  required ForumHtmlReaderPreferences preferences,
  ForumHtmlRenderCallbacks callbacks = const ForumHtmlRenderCallbacks(),
}) {
  final request = preparedBody.request;
  final chunk = preparedBody.document.safeDisplayPlan!.chunks[ordinal];
  return ForumHtmlWidgetPostRenderer(
    html: chunk.html,
    theme: request.theme,
    preferences: preferences,
    preparedDocument: preparedBody.document.copyWith(
      preparedHtml: chunk.html,
      clearSafeDisplayPlan: true,
    ),
    sourceId: request.sourceId,
    threadId: request.threadId,
    hasTrailingContent: chunk.hasTrailingContent,
    callbacks: callbacks,
  );
}

/// Only demanded chunks own renderer Elements; page memory contains pure values.
class _ThreadPostChunkBody extends ConsumerStatefulWidget {
  const _ThreadPostChunkBody({
    required this.preparedBody,
    required this.ordinal,
    required this.post,
    required this.sourcePost,
    required this.theme,
    required this.onPreparedBody,
    this.preparerSelector,
    required this.onOpenPostLink,
  });

  final ThreadDetailPreparedBody preparedBody;
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
  final _preparation = ForumHtmlPreparationController();
  double? _previousHeight;

  @override
  void initState() {
    super.initState();
    _preparation.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _preparation.dispose();
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
      threadId: widget.preparedBody.request.threadId,
      imageCacheOwnerId: widget.preparedBody.request.imageCacheOwnerId,
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
    final previousBox = _key.currentContext?.findRenderObject();
    if (previousBox is RenderBox && previousBox.hasSize) {
      _previousHeight = previousBox.size.height;
    }
    if (request.identity != widget.preparedBody.request.identity) {
      ForumHtmlPreparedRenderDocument? document;
      try {
        document = _preparation.resolve(request);
      } catch (_) {
        // The whole-body owner supplies the existing error/retry presentation.
        document = widget.preparedBody.document.copyWith(
          preparedHtml: request.html,
          clearSafeDisplayPlan: true,
        );
      }
      if (document != null) widget.onPreparedBody(context, request, document);
      // Keep the last actual chunk height while its replacement is prepared.
      return SizedBox(
        height: _previousHeight ?? 48,
        child: const ForumHtmlPreparationPlaceholder(),
      );
    }
    _preparation.reset();
    return KeyedSubtree(
      key: _key,
      child: KeyedSubtree(
        key: Key('thread-post-html-first-body-${request.sourceId}'),
        child: _chunkRenderer(
          widget.preparedBody,
          widget.ordinal,
          preferences: preferences,
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
}
