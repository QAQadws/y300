import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

class ThreadPostHtmlSelectionCopyPage extends StatelessWidget {
  const ThreadPostHtmlSelectionCopyPage({
    super.key,
    required this.post,
    required this.threadId,
    required this.imageReferer,
    required this.plan,
    required this.imageHeaderBuilder,
    required this.onOpenPostLink,
    required this.onOpenPostImage,
    required this.onImageFallback,
  });

  final ThreadPost post;
  final String threadId;
  final String imageReferer;
  final ThreadPostBodyRenderPlan plan;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<String> onOpenPostLink;
  final void Function(ThreadPost post, ThreadPostImageOpenRequest request)?
  onOpenPostImage;
  final ThreadPostHtmlFirstImageFallback onImageFallback;

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    return Scaffold(
      key: const Key('thread-post-html-selection-copy-page'),
      backgroundColor: palette.background,
      appBar: AppBar(centerTitle: false, title: const Text('选择复制')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          children: [
            Container(
              key: Key('thread-post-html-selection-copy-body-${post.pid}'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
              ),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.bodyText,
                  height: 1.5,
                ),
                child: ThreadPostHtmlBody(
                  post: post,
                  threadId: threadId,
                  imageReferer: imageReferer,
                  plan: plan,
                  imageHeaderBuilder: imageHeaderBuilder,
                  onOpenPostLink: onOpenPostLink,
                  onOpenPostImage: onOpenPostImage,
                  theme: const ForumHtmlRenderThemeFactory().fromThreadPalette(
                    palette: palette,
                    brightness: Theme.of(context).brightness,
                  ),
                  onImageFallback: onImageFallback,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
