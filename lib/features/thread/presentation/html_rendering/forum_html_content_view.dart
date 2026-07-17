import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

class ForumHtmlContentView extends ConsumerWidget {
  const ForumHtmlContentView({
    super.key,
    required this.html,
    required this.sourceId,
    this.imageHeaderBuilder,
    this.imageCacheOwnerId,
    this.contentImageKind = ForumImageKind.blogInline,
    this.onOpenLink,
    this.theme,
    this.surfaceColor,
    this.foregroundColor,
  });

  final String html;
  final String sourceId;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String? imageCacheOwnerId;
  final ForumImageKind contentImageKind;
  final ValueChanged<String>? onOpenLink;
  final ForumHtmlThemeContext? theme;
  final Color? surfaceColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trimmedHtml = html.trim();
    if (trimmedHtml.isEmpty) {
      return const SizedBox.shrink();
    }
    final ownerId = _ownerId();
    final preferences =
        ref.watch(forumHtmlReaderPreferencesControllerProvider).value ??
        ForumHtmlReaderPreferences.defaults();
    final materialTheme = Theme.of(context);
    final renderTheme =
        theme ??
        const ForumHtmlRenderThemeFactory().fromMaterialTheme(
          theme: materialTheme,
          surface: surfaceColor ?? materialTheme.colorScheme.surface,
          foreground: foregroundColor,
        );
    return ForumHtmlWidgetPostRenderer(
      html: trimmedHtml,
      theme: renderTheme,
      sourceId: sourceId.trim().isEmpty ? ownerId : sourceId.trim(),
      threadId: ownerId,
      imageHeaderBuilder: imageHeaderBuilder,
      imageCacheOwnerId: ownerId,
      preferences: preferences,
      contentImageKind: contentImageKind,
      callbacks: ForumHtmlRenderCallbacks(
        onTapUrl: (url) {
          onOpenLink?.call(url);
          return true;
        },
      ),
    );
  }

  String _ownerId() {
    final owner = imageCacheOwnerId?.trim();
    if (owner != null && owner.isNotEmpty) {
      return owner;
    }
    final source = sourceId.trim();
    return source.isEmpty ? 'html-content' : source;
  }
}
