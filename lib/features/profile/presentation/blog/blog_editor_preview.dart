import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

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
    final title = const HtmlEscape(
      HtmlEscapeMode.element,
    ).convert(draft.subject);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: native.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: ForumNativeSurfaceShadows.card(native.stateLayer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ForumHtmlContentView(
          html: '<h2>$title</h2>${draft.bodyHtml}',
          sourceId: 'blog-editor-preview-$ownerId',
          imageCacheOwnerId: ownerId,
          imageReferer: ref.watch(forumImageRefererProvider),
          surfaceColor: native.card,
          foregroundColor: native.body,
        ),
      ),
    );
  }
}
