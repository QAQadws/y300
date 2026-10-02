import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/features/profile/presentation/blog/blog_quill_html_codec.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';

StickerItem blogEditorSticker(String url) => StickerItem(
  code: url,
  rawCodePattern: url,
  imagePath: Uri.parse(url).path,
  imageUrl: url,
  cacheKey: url,
);

class BlogImageEmbedBuilder extends EmbedBuilder {
  const BlogImageEmbedBuilder({required this.previews});
  final Map<String, String> previews;
  @override
  String get key => blogQuillImageEmbedType;
  @override
  bool get expanded => false;
  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final payload = blogQuillImagePayload(embedContext.node.value.data);
    if (payload == null) return const SizedBox.shrink();
    final src = payload['src']!;
    if (RegExp(
      r'/smiley/comcom/\d+\.gif$',
    ).hasMatch(Uri.tryParse(src)?.path ?? '')) {
      return Consumer(
        builder: (context, ref, _) => ComposerStickerImage(
          sticker: blogEditorSticker(
            ref
                .watch(yamiboForumClientConfigProvider)
                .siteOrigin
                .resolve(src)
                .toString(),
          ),
          width: 32,
          height: 32,
          placeholder: const SizedBox(width: 32, height: 32),
          errorPlaceholder: const Icon(Icons.broken_image_outlined, size: 24),
        ),
      );
    }
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(80.0, 720.0);
    final path = previews[src];
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: 480),
      child: path != null
          ? Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            )
          : SizedBox(
              width: width,
              child: BlogPreservedHtml(html: payload['html']!, id: src),
            ),
    );
  }
}

class BlogHtmlEmbedBuilder extends EmbedBuilder {
  const BlogHtmlEmbedBuilder();
  @override
  String get key => blogQuillHtmlEmbedType;
  @override
  bool get expanded => true;
  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      BlogPreservedHtml(
        html: blogQuillHtmlSource(embedContext.node.value.data) ?? '',
        id: '${embedContext.node.documentOffset}',
      );
}

/// Unknown legacy structures remain visible and round-trip without rewriting.
class BlogPreservedHtml extends ConsumerWidget {
  const BlogPreservedHtml({super.key, required this.html, required this.id});
  final String html;
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ForumHtmlContentView(
    html: html,
    sourceId: 'blog-editor-preserved-$id',
    theme: const ForumHtmlRenderThemeFactory().fromNativeTheme(
      theme: Theme.of(context),
    ),
    imageReferer: ref.watch(forumImageRefererProvider),
  );
}
