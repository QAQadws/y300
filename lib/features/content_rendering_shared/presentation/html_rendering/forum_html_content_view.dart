import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../application/forum_html_image_host_provider.dart';
import '../../application/forum_html_preparation_controller.dart';
import '../../application/forum_html_preparation_executor.dart';
import '../../application/forum_html_reader_font_binding.dart';
import '../../application/forum_html_reader_preferences_controller.dart';
import '../../application/forum_html_render_preferences_projection.dart';
import '../../application/forum_html_render_preparer.dart';
import '../../domain/models/forum_html_reader_preferences.dart';
import '../contracts/forum_html_render_preparer.dart';
import 'forum_html_preparation_placeholder.dart';
import 'forum_html_reader_text_style.dart';
import 'forum_native_body_flow.dart';

/// Prepared HTML rendered as native document or compact content flow.
class ForumHtmlContentView extends ConsumerStatefulWidget {
  const ForumHtmlContentView({
    super.key,
    required this.html,
    required this.sourceId,
    this.imageReferer,
    this.imageCacheOwnerId,
    this.contentImageKind = ForumImageKind.blogInline,
    this.contentLayout = ForumHtmlContentLayout.document,
    this.onOpenLink,
    this.onOpenImage,
    this.imageAnchorController,
    this.bodyPresentation,
    this.theme,
    this.surfaceColor,
    this.foregroundColor,
    this.renderPreparer,
    this.preparationExecutor,
    this.linkBaseUri,
    this.useSharedReaderFont = false,
    this.selectEntireBody = false,
    this.isCurrent,
  });

  final String html;
  final String sourceId;
  final String? imageReferer;
  final String? imageCacheOwnerId;
  final ForumImageKind contentImageKind;
  final ForumHtmlContentLayout contentLayout;
  final ValueChanged<String>? onOpenLink;
  final void Function(ForumHtmlReadableImageSequence, ForumHtmlImageRequest)?
  onOpenImage;
  final ForumHtmlImageAnchorController? imageAnchorController;
  final ForumHtmlBodyPresentation? bodyPresentation;
  final ForumHtmlThemeContext? theme;
  final Color? surfaceColor;
  final Color? foregroundColor;
  final ForumHtmlRenderPreparer? renderPreparer;
  final ForumHtmlPreparationExecutor? preparationExecutor;
  final Uri? linkBaseUri;
  final bool useSharedReaderFont;
  final bool selectEntireBody;
  final bool Function()? isCurrent;

  @override
  ConsumerState<ForumHtmlContentView> createState() =>
      _ForumHtmlContentViewState();
}

class _ForumHtmlContentViewState extends ConsumerState<ForumHtmlContentView> {
  // Preparation identity includes the preparer. These immutable defaults must
  // keep the same identity when a virtualized body mounts again.
  static final _defaultPreparers = {
    for (final kind in ForumImageKind.values)
      kind: DefaultForumHtmlRenderPreparer(contentImageKind: kind),
  };
  late var _preparation = _createPreparation();
  late var _defaultPreparer = _defaultPreparers[widget.contentImageKind]!;
  Object? _nativeSource;
  var _expansion = <String, bool>{};
  Object? _imageHostIdentity;
  ForumHtmlImageHost? _imageHost;
  Object? _layoutRevision;
  String? _layoutSourceId;
  var _layoutPhase = ForumHtmlBodyLayoutPhase.preparing;

  ForumHtmlPreparationController _createPreparation() =>
      ForumHtmlPreparationController(executor: widget.preparationExecutor)
        ..addListener(_onPreparationChanged);

  void _onPreparationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ForumHtmlContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preparationExecutor != widget.preparationExecutor) {
      _preparation.dispose();
      _preparation = _createPreparation();
    }
    if (oldWidget.contentImageKind != widget.contentImageKind) {
      _defaultPreparer = _defaultPreparers[widget.contentImageKind]!;
    }
    if (_preparation.hasError) _preparation.reset();
  }

  @override
  void dispose() {
    _preparation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildContent(context);
    final presentation = widget.bodyPresentation;
    final revision = _layoutRevision;
    if (presentation == null || revision == null) return body;
    return ForumHtmlBodyLayout.observed(
      presentation: presentation,
      sourceId: _layoutSourceId!,
      revision: revision,
      phase: () => _layoutPhase,
      child: body,
    );
  }

  Widget _buildContent(BuildContext context) {
    final trimmedHtml = widget.html.trim();
    if (trimmedHtml.isEmpty) {
      _preparation.reset();
      _nativeSource = null;
      _layoutRevision = null;
      return const SizedBox.shrink();
    }
    final ownerId = _ownerId();
    final fontBinding = widget.useSharedReaderFont
        ? ref.watch(forumHtmlReaderFontBindingProvider)
        : null;
    if (fontBinding != null && !fontBinding.isReady) {
      _layoutRevision = null;
      _layoutPhase = ForumHtmlBodyLayoutPhase.preparing;
      return const ForumHtmlPreparationPlaceholder();
    }
    final preferences =
        fontBinding?.preferences ??
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
    final request = ForumHtmlPreparationRequest(
      html: trimmedHtml,
      preferences: preferences,
      theme: renderTheme,
      sourceId: sourceId,
      threadId: ownerId,
      imageCacheOwnerId: ownerId,
      preparer: widget.renderPreparer ?? _defaultPreparer,
    );
    final textStyle = fontBinding == null
        ? resolveForumHtmlBaseTextStyle(
            context,
            options: preferences.renderOptions,
            theme: renderTheme,
          )
        : resolveForumHtmlReaderTextStyle(
            context,
            preferences: preferences,
            theme: renderTheme,
            font: fontBinding.resolvedFont,
          );
    final revision = (
      request.identity,
      preferences.renderOptions,
      textStyle,
      fontBinding?.cacheKey,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      Localizations.localeOf(context),
      widget.contentLayout,
    );
    if (_layoutRevision != revision) {
      _layoutRevision = revision;
      _layoutPhase = ForumHtmlBodyLayoutPhase.preparing;
    }
    _layoutSourceId = sourceId;
    ForumHtmlPreparedRenderDocument? document;
    try {
      document = _preparation.resolve(request);
    } catch (_) {
      _layoutPhase = ForumHtmlBodyLayoutPhase.failed;
      final l10n = AppLocalizations.of(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.threadHtmlRenderFailed),
          TextButton(
            onPressed: () => setState(_preparation.reset),
            child: Text(l10n.commonRetry),
          ),
        ],
      );
    }
    if (document == null) {
      _layoutPhase = ForumHtmlBodyLayoutPhase.preparing;
      return const ForumHtmlPreparationPlaceholder();
    }
    final source = (
      trimmedHtml,
      sourceId,
      ownerId,
      request.preparer,
      widget.bodyPresentation,
    );
    if (_nativeSource != source) {
      _nativeSource = source;
      _expansion = widget.bodyPresentation?.collapseExpansion ?? {};
      _layoutPhase = ForumHtmlBodyLayoutPhase.preparing;
    }
    final requestIdentity = request.identity;
    bool current() =>
        mounted &&
        _preparation.identity == requestIdentity &&
        (widget.isCurrent?.call() ?? true);
    final expansion = _expansion;
    return ForumNativeBodyFlow(
      key: ObjectKey(_expansion),
      prepared: document,
      preferences: preferences,
      contentLayout: widget.contentLayout,
      theme: renderTheme,
      textStyle: textStyle,
      fontRevision: fontBinding?.cacheKey ?? '',
      imageHost: _resolveImageHost(document, ownerId),
      imageAnchorController: widget.imageAnchorController,
      bodyPresentation: widget.bodyPresentation,
      expansion: _expansion,
      onLayoutPhase: (phase) {
        if (current() && identical(_expansion, expansion)) _layoutPhase = phase;
      },
      onOpenImage: widget.onOpenImage == null
          ? null
          : (gallery, image) {
              if (current()) widget.onOpenImage?.call(gallery, image);
            },
      callbacks: ForumHtmlRenderCallbacks(
        onTapUrl: widget.onOpenLink == null
            ? null
            : (url) {
                if (!current()) return false;
                final uri = Uri.tryParse(url.trim());
                if (uri == null) return false;
                final base = widget.linkBaseUri ?? AppConfig.siteBaseUri;
                widget.onOpenLink?.call(base.resolveUri(uri).toString());
                return true;
              },
      ),
      clipboardTextWriter: ref.read(clipboardTextWriterProvider),
      selectionEnabled: widget.selectEntireBody,
      selectEntireBody: widget.selectEntireBody,
      isSelectionCurrent: current,
      errorBuilder: (context) =>
          Text(AppLocalizations.of(context).threadHtmlRenderFailed),
    );
  }

  ForumHtmlImageHost? _resolveImageHost(
    ForumHtmlPreparedRenderDocument document,
    String ownerId,
  ) {
    if (document.sequence.entries.isEmpty &&
        document.skippedStickerCount == 0) {
      _imageHostIdentity = null;
      return _imageHost = null;
    }
    final host = ref.watch(forumHtmlImageHostProvider);
    final identity = (
      host,
      ownerId,
      widget.imageReferer,
      widget.contentImageKind,
    );
    if (_imageHostIdentity != identity) {
      _imageHostIdentity = identity;
      _imageHost = host.forContent(
        threadId: ownerId,
        imageCacheOwnerId: ownerId,
        imageReferer: widget.imageReferer,
        contentImageKind: widget.contentImageKind,
      );
    }
    return _imageHost;
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
