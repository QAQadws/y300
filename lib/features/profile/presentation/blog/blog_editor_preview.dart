import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/profile/presentation/blog/blog_surface.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';

/// Preview is mounted only on demand. It uses the shared HTML reader without
/// converting its rendered or translated text back into the editable source.
class BlogEditorPreview extends ConsumerWidget {
  const BlogEditorPreview({
    super.key,
    required this.draft,
    required this.ownerId,
  });
  final BlogEditorDraft draft;
  final String ownerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final native = Theme.of(context).y300NativeContent;
    final accountOwner = ref.watch(blogMutationBusProvider);
    final referer = ref.watch(forumImageRefererProvider);
    final display = watchBlogDisplayText(
      ref,
      BlogContentSource(text: [draft.subject], html: [draft.bodyHtml]),
    );
    final title = const HtmlEscape(
      HtmlEscapeMode.element,
    ).convert(display.text(draft.subject));
    return BlogSurface(
      child: ForumHtmlContentView(
        html: '<h2>$title</h2>${display.html(draft.bodyHtml)}',
        sourceId: 'blog-editor-preview-$ownerId',
        onOpenImage: (sequence, image) => openBlogImageReader(
          context,
          ref,
          accountOwner: accountOwner,
          sequence: sequence,
          image: image,
          cacheOwnerId: ownerId,
          referer: referer,
        ),
        imageCacheOwnerId: ownerId,
        imageReferer: referer,
        surfaceColor: native.card,
        foregroundColor: native.body,
      ),
    );
  }
}
