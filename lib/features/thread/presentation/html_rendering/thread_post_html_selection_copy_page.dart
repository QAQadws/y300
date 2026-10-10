import 'package:y300/app/content_rendering/native_forum_html_render_theme_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/forum_selected_link_policy.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';
import 'package:y300/l10n/app_localizations.dart';

class ThreadPostHtmlSelectionCopyPage extends ConsumerStatefulWidget {
  const ThreadPostHtmlSelectionCopyPage({
    super.key,
    required this.post,
    this.sourcePost,
    required this.threadId,
    required this.imageReferer,
    required this.onOpenPostLink,
    required this.onOpenPostImage,
    required this.onImageFallback,
    this.onOpenSelectedPostLink,
    this.isCurrent,
    this.renderPreparer = const DefaultForumHtmlRenderPreparer(),
  });

  final ThreadPost post;
  final ThreadPost? sourcePost;
  final String threadId;
  final String imageReferer;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadImageOpenRequest request)?
  onOpenPostImage;
  final ThreadPostHtmlFirstImageFallback onImageFallback;
  final ForumHtmlRenderPreparer renderPreparer;
  final ForumSelectionLinkOpener? onOpenSelectedPostLink;
  final bool Function()? isCurrent;

  @override
  ConsumerState<ThreadPostHtmlSelectionCopyPage> createState() =>
      _ThreadPostHtmlSelectionCopyPageState();
}

class _ThreadPostHtmlSelectionCopyPageState
    extends ConsumerState<ThreadPostHtmlSelectionCopyPage> {
  ForumSelectedLinkSource? _linkSource;
  int _sourceGeneration = 0;

  @override
  void initState() {
    super.initState();
    _prepareSource();
  }

  @override
  void didUpdateWidget(ThreadPostHtmlSelectionCopyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.message != widget.post.message ||
        (oldWidget.onOpenSelectedPostLink == null) !=
            (widget.onOpenSelectedPostLink == null)) {
      _prepareSource();
    } else if (oldWidget.onOpenSelectedPostLink !=
        widget.onOpenSelectedPostLink) {
      _sourceGeneration++;
    }
  }

  void _prepareSource() {
    _sourceGeneration++;
    // The rendered selection offsets are not HTML coordinates. Cache complete
    // source URLs once, rather than projecting those offsets or rescanning on
    // every toolbar rebuild.
    _linkSource = widget.onOpenSelectedPostLink == null
        ? null
        : ForumSelectedLinkSource.fromHtml(widget.post.message);
  }

  String? _resolveSelection(String text) {
    final url = const ForumSelectedLinkPolicy().resolve(text);
    return url != null && _linkSource?.confirms(url) == true ? url : null;
  }

  Future<void> _openSelection(String url, bool Function() isCurrent) async {
    final generation = _sourceGeneration;
    await widget.onOpenSelectedPostLink?.call(
      url,
      () => mounted && generation == _sourceGeneration && isCurrent(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    return ForumContentSelectionCopyPage(
      key: const Key('thread-post-html-selection-copy-page'),
      title: AppLocalizations.of(context).threadSelectionCopyTitle,
      bodyKey: Key(
        'thread-post-html-selection-copy-body-${(widget.sourcePost ?? widget.post).pid}',
      ),
      resolveForumLink: widget.onOpenSelectedPostLink == null
          ? null
          : _resolveSelection,
      onOpenForumLink: widget.onOpenSelectedPostLink == null
          ? null
          : _openSelection,
      clipboardTextWriter: ref.watch(clipboardTextWriterProvider),
      isCurrent: widget.isCurrent,
      child: ThreadPostHtmlBody(
        post: widget.post,
        sourcePost: widget.sourcePost,
        renderPreparer: widget.renderPreparer,
        threadId: widget.threadId,
        imageReferer: widget.imageReferer,
        onOpenPostLink: widget.onOpenPostLink,
        onOpenPostImage: widget.onOpenPostImage,
        theme: const ForumHtmlRenderThemeFactory().fromThreadPalette(
          palette: palette,
          brightness: Theme.of(context).brightness,
        ),
        onImageFallback: widget.onImageFallback,
      ),
    );
  }
}
