import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';
import 'package:y300/l10n/app_localizations.dart';

class ThreadPostHtmlSelectionCopyPage extends StatelessWidget {
  const ThreadPostHtmlSelectionCopyPage({
    super.key,
    required this.post,
    this.sourcePost,
    required this.threadId,
    required this.imageReferer,
    required this.onOpenPostLink,
    required this.onOpenPostImage,
    required this.onImageFallback,
  });

  final ThreadPost post;
  final ThreadPost? sourcePost;
  final String threadId;
  final String imageReferer;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadImageOpenRequest request)?
  onOpenPostImage;
  final ThreadPostHtmlFirstImageFallback onImageFallback;

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    return ForumContentSelectionCopyPage(
      key: const Key('thread-post-html-selection-copy-page'),
      title: AppLocalizations.of(context).threadSelectionCopyTitle,
      bodyKey: Key(
        'thread-post-html-selection-copy-body-${(sourcePost ?? post).pid}',
      ),
      child: ThreadPostHtmlBody(
        post: post,
        sourcePost: sourcePost,
        threadId: threadId,
        imageReferer: imageReferer,
        onOpenPostLink: onOpenPostLink,
        onOpenPostImage: onOpenPostImage,
        theme: const ForumHtmlRenderThemeFactory().fromThreadPalette(
          palette: palette,
          brightness: Theme.of(context).brightness,
        ),
        onImageFallback: onImageFallback,
      ),
    );
  }
}
