import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

class ForumHtmlContentView extends ConsumerStatefulWidget {
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
    this.renderPreparer = const DefaultForumHtmlRenderPreparer(),
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
  final ForumHtmlRenderPreparer renderPreparer;

  @override
  ConsumerState<ForumHtmlContentView> createState() =>
      _ForumHtmlContentViewState();
}

class _ForumHtmlContentViewState extends ConsumerState<ForumHtmlContentView> {
  Object? _preparationIdentity;
  ForumHtmlPreparedRenderDocument? _preparedDocument;

  @override
  Widget build(BuildContext context) {
    final trimmedHtml = widget.html.trim();
    if (trimmedHtml.isEmpty) {
      _preparationIdentity = null;
      _preparedDocument = null;
      return const SizedBox.shrink();
    }
    final ownerId = _ownerId();
    final preferences =
        ref.watch(forumHtmlReaderPreferencesControllerProvider).value ??
        ForumHtmlReaderPreferences.defaults();
    final materialTheme = Theme.of(context);
    final renderTheme =
        widget.theme ??
        const ForumHtmlRenderThemeFactory().fromMaterialTheme(
          theme: materialTheme,
          surface: widget.surfaceColor ?? materialTheme.colorScheme.surface,
          foreground: widget.foregroundColor,
        );
    final sourceId = widget.sourceId.trim().isEmpty
        ? ownerId
        : widget.sourceId.trim();
    final preparationIdentity = (
      html: trimmedHtml,
      preferences: preferences,
      themeSignature: renderTheme.signature,
      sourceId: sourceId,
      ownerId: ownerId,
      preparer: widget.renderPreparer,
    );
    if (_preparationIdentity != preparationIdentity) {
      final preparedDocument = widget.renderPreparer.prepare(
        html: trimmedHtml,
        preferences: preferences,
        theme: renderTheme,
        themeAdaptationMode: ForumHtmlThemeAdaptationMode.enabled,
        sourceId: sourceId,
        threadId: ownerId,
        imageCacheOwnerId: ownerId,
      );
      _preparationIdentity = preparationIdentity;
      _preparedDocument = preparedDocument;
    }
    return ForumHtmlWidgetPostRenderer(
      html: trimmedHtml,
      theme: renderTheme,
      sourceId: sourceId,
      threadId: ownerId,
      imageHeaderBuilder: widget.imageHeaderBuilder,
      imageCacheOwnerId: ownerId,
      preferences: preferences,
      preparedDocument: _preparedDocument,
      contentImageKind: widget.contentImageKind,
      callbacks: ForumHtmlRenderCallbacks(
        onTapUrl: (url) {
          widget.onOpenLink?.call(url);
          return true;
        },
      ),
    );
  }

  String _ownerId() {
    final owner = widget.imageCacheOwnerId?.trim();
    if (owner != null && owner.isNotEmpty) {
      return owner;
    }
    final source = widget.sourceId.trim();
    return source.isEmpty ? 'html-content' : source;
  }
}
