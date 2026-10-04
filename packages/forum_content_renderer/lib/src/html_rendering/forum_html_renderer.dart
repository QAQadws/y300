import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import '../models/forum_html_content_layout.dart';
import '../models/forum_html_render_options.dart';
import '../contracts/forum_html_collapse_labels.dart';
import '../contracts/forum_html_image_host.dart';
import '../services/forum_html_body_presentation.dart';
import '../services/forum_html_image_viewport_coordinator.dart';
import 'forum_html_image_widget_factory.dart';
import 'forum_html_prepared_render_document.dart';
import 'forum_html_render_callbacks.dart';
import 'forum_html_render_style_policy.dart';
import 'theme/forum_html_theme_context.dart';
import 'widgets/forum_collapse_block.dart';

/// Rendering only: preparation, localization and image ownership belong to Host.
class ForumHtmlRenderer extends StatefulWidget {
  const ForumHtmlRenderer({
    super.key,
    required this.preparedDocument,
    required this.theme,
    required this.options,
    required this.labels,
    this.callbacks = const ForumHtmlRenderCallbacks(),
    this.textStyle,
    this.textAlign,
    this.imageHost,
    this.imageHostRevision,
    this.imageViewportCoordinator,
    this.buildAsync,
    this.enableCaching,
    this.renderMode = RenderMode.column,
    this.onBodyBuilt,
    this.bodyPresentation,
    this.collapseExpansion,
    this.sourceId,
    this.blockSpacingMode = ForumHtmlBlockSpacingMode.paragraphLikeDivs,
    this.linkBaseUri,
    this.contentLayout = ForumHtmlContentLayout.document,
  });

  final ForumHtmlPreparedRenderDocument preparedDocument;
  final ForumHtmlThemeContext theme;
  final ForumHtmlRenderOptions options;
  final ForumHtmlCollapseLabels labels;
  final ForumHtmlRenderCallbacks callbacks;

  /// Resolved unscaled base style; overrides the default fontScale projection.
  /// Author CSS and block spacing still use the normal style policy.
  final TextStyle? textStyle;
  final TextAlign? textAlign;
  final ForumHtmlImageHost? imageHost;

  /// Stable identity for a Host assembled on each build. Defaults to the Host.
  final Object? imageHostRevision;
  final ForumHtmlImageViewportCoordinator? imageViewportCoordinator;
  final bool? buildAsync;
  final bool? enableCaching;
  final RenderMode renderMode;
  final VoidCallback? onBodyBuilt;
  final ForumHtmlBodyPresentation? bodyPresentation;
  final Map<String, bool>? collapseExpansion;
  final String? sourceId;
  final ForumHtmlBlockSpacingMode blockSpacingMode;
  final Uri? linkBaseUri;
  final ForumHtmlContentLayout contentLayout;

  @override
  State<ForumHtmlRenderer> createState() => _ForumHtmlRendererState();
}

class _ForumHtmlRendererState extends State<ForumHtmlRenderer> {
  late final _binding = ValueNotifier<ForumHtmlImageFactoryBinding>((
    host: widget.imageHost,
    viewport: widget.imageViewportCoordinator,
    handlesImageTap: widget.callbacks.onTapImage != null,
  ));
  // fwfh retains its factory and cached custom widgets. Events read current
  // values; folds listen for config updates without losing expansion state.
  late final _configuration = ValueNotifier(widget);
  VoidCallback? _onReady;

  @override
  void didUpdateWidget(covariant ForumHtmlRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hostChanged =
        (oldWidget.imageHostRevision ?? oldWidget.imageHost) !=
        (widget.imageHostRevision ?? widget.imageHost);
    if (hostChanged ||
        (oldWidget.callbacks.onTapImage == null) !=
            (widget.callbacks.onTapImage == null) ||
        !identical(
          oldWidget.imageViewportCoordinator,
          widget.imageViewportCoordinator,
        )) {
      _binding.value = (
        host: hostChanged ? widget.imageHost : _binding.value.host,
        viewport: widget.imageViewportCoordinator,
        handlesImageTap: widget.callbacks.onTapImage != null,
      );
    }
    _configuration.value = widget;
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.preparedDocument;
    final themeMatches = document.themeSignature == widget.theme.signature;
    assert(
      themeMatches,
      'Forum HTML prepared document theme mismatch for ${widget.sourceId ?? 'anonymous'}.',
    );
    if (!themeMatches) {
      return const SizedBox.shrink(
        key: Key('forum-html-renderer-theme-mismatch'),
      );
    }
    final stylePolicy = ForumHtmlRenderStylePolicy(
      widget.options,
      theme: widget.theme,
      blockSpacingMode: widget.blockSpacingMode,
      contentLayout: widget.contentLayout,
    );
    final binding =
        context
            .getInheritedWidgetOfExactType<_ForumHtmlInheritedHostBinding>()
            ?.binding ??
        _binding;
    final baseStyle = widget.textStyle ?? stylePolicy.baseTextStyle(context);
    Widget buildBody(VoidCallback? ready) {
      _onReady = ready;
      final body = HtmlWidget(
        document.preparedHtml,
        key: Key('forum-html-renderer-${widget.sourceId ?? 'anonymous'}'),
        baseUrl: widget.linkBaseUri,
        onErrorBuilder: (_, _, _) {
          _onReady?.call();
          return null;
        },
        buildAsync: widget.buildAsync,
        customStylesBuilder: stylePolicy.customStylesFor,
        customWidgetBuilder: (element) =>
            _buildCustomWidget(element, stylePolicy, document, binding),
        factoryBuilder: () => ForumHtmlImageWidgetFactory(
          binding: binding,
          textAlignFor: () => _configuration.value.textAlign,
          onBodyBuilt: () => _onReady?.call(),
          onTapImageRequest: (request) {
            final callback = widget.callbacks.onTapImage;
            if (callback == null) return;
            widget.callbacks.onInteraction?.call();
            callback(request);
          },
          onImageLayoutShift: (shift) =>
              widget.callbacks.onImageLayoutShift?.call(shift),
          readableImageKeyPrefix: widget.sourceId == null
              ? null
              : 'thread-post-html-first-readable-image-${widget.sourceId}',
        ),
        enableCaching: widget.enableCaching,
        renderMode: widget.renderMode,
        rebuildTriggers: [
          widget.options,
          widget.textStyle,
          widget.textAlign,
          widget.theme.signature,
          widget.blockSpacingMode,
          widget.contentLayout,
          widget.linkBaseUri,
        ],
        textStyle: baseStyle,
        onTapUrl: (url) {
          final callback = widget.callbacks.onTapUrl;
          if (callback == null) return false;
          widget.callbacks.onInteraction?.call();
          return callback(url);
        },
      );
      // fwfh retains its factory and root properties. An alignment-only change
      // must invalidate inherited root properties without remounting the body.
      return DefaultTextStyle.merge(
        textAlign: widget.textAlign ?? TextAlign.start,
        child: body,
      );
    }

    final presentation = widget.bodyPresentation;
    if (presentation == null || widget.renderMode != RenderMode.column) {
      return buildBody(widget.onBodyBuilt);
    }
    final revision = (
      document.preparedHtml,
      baseStyle,
      widget.textAlign,
      MediaQuery.textScalerOf(context),
      widget.options,
      widget.theme.signature,
      widget.blockSpacingMode,
      widget.contentLayout,
      widget.linkBaseUri,
    );
    return ForumHtmlBodyLayout(
      key: ValueKey((presentation, revision)),
      presentation: presentation,
      sourceId: widget.sourceId ?? 'anonymous',
      revision: revision,
      builder: (ready) => buildBody(() {
        ready();
        widget.onBodyBuilt?.call();
      }),
    );
  }

  Widget? _buildCustomWidget(
    html_dom.Element element,
    ForumHtmlRenderStylePolicy stylePolicy,
    ForumHtmlPreparedRenderDocument document,
    ValueNotifier<ForumHtmlImageFactoryBinding> binding,
  ) {
    if (stylePolicy.isDiscuzEditStatusElement(element)) {
      return _DiscuzEditStatusText(
        text: element.text.trim(),
        baseStyle: (context) =>
            widget.textStyle ?? stylePolicy.baseTextStyle(context),
      );
    }
    if (!stylePolicy.isForumCollapseElement(element)) return null;
    final collapseId = _collapseSourceId(element);
    final titleHtml = _firstChildWithClass(
      element,
      'showcollapse_title',
    )?.innerHtml;
    final contentHtml = _collapseContentHtml(element);
    return ValueListenableBuilder<ForumHtmlRenderer>(
      valueListenable: _configuration,
      builder: (context, configuration, _) => ForumCollapseBlock(
        titleHtml:
            titleHtml ??
            const HtmlEscape().convert(configuration.labels.fallbackTitle),
        contentHtml: contentHtml,
        labels: configuration.labels,
        initiallyExpanded:
            configuration.collapseExpansion?[collapseId] ??
            stylePolicy.isForumCollapseInitiallyExpanded(element),
        onExpandedChanged: (expanded) =>
            configuration.collapseExpansion?[collapseId] = expanded,
        sourceId: collapseId,
        onInteraction: () => widget.callbacks.onInteraction?.call(),
        nestedRendererBuilder: (html, {required sourceId}) =>
            _ForumHtmlInheritedHostBinding(
              binding: binding,
              child: ForumHtmlRenderer(
                preparedDocument: document.copyWith(preparedHtml: html),
                theme: configuration.theme,
                options: configuration.options,
                textStyle: configuration.textStyle,
                textAlign: configuration.textAlign,
                labels: configuration.labels,
                callbacks: configuration.callbacks,
                collapseExpansion: configuration.collapseExpansion,
                bodyPresentation: configuration.bodyPresentation,
                buildAsync: configuration.buildAsync,
                enableCaching: configuration.enableCaching,
                sourceId: sourceId,
                blockSpacingMode: configuration.blockSpacingMode,
                contentLayout: configuration.contentLayout,
                linkBaseUri: configuration.linkBaseUri,
              ),
            ),
      ),
    );
  }

  @override
  void dispose() {
    _binding.dispose();
    _configuration.dispose();
    super.dispose();
  }

  String _collapseContentHtml(html_dom.Element element) {
    final content = _firstChildWithClass(element, 'showcollapse_content');
    if (content == null) {
      return '';
    }
    final clone = html_parser.parseFragment(content.innerHtml);
    for (final gather in clone.querySelectorAll('.showcollapse_gather')) {
      gather.remove();
    }
    return clone.nodes.map(_serializeNode).join();
  }

  html_dom.Element? _firstChildWithClass(
    html_dom.Element element,
    String className,
  ) {
    for (final child in element.children) {
      if (child.classes.contains(className)) {
        return child;
      }
    }
    return null;
  }

  String _collapseSourceId(html_dom.Element element) {
    final id = element.id;
    if (id.isNotEmpty) {
      return '${widget.sourceId ?? 'anonymous'}-$id';
    }
    final title = _firstChildWithClass(element, 'showcollapse_title');
    final titleText = title?.text.trim();
    if (titleText != null && titleText.isNotEmpty) {
      return '${widget.sourceId ?? 'anonymous'}-${_stableHash(titleText)}';
    }
    return '${widget.sourceId ?? 'anonymous'}-${_stableHash(element.outerHtml)}';
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
  }
}

class _ForumHtmlInheritedHostBinding extends InheritedWidget {
  const _ForumHtmlInheritedHostBinding({
    required this.binding,
    required super.child,
  });
  final ValueNotifier<ForumHtmlImageFactoryBinding> binding;
  @override
  bool updateShouldNotify(_ForumHtmlInheritedHostBinding oldWidget) =>
      !identical(binding, oldWidget.binding);
}

class _DiscuzEditStatusText extends StatelessWidget {
  const _DiscuzEditStatusText({required this.text, required this.baseStyle});

  static final _whitespace = RegExp(r'[\s\u0085\u00a0\u2028\u2029]+');

  final String text;
  final TextStyle Function(BuildContext context) baseStyle;

  @override
  Widget build(BuildContext context) {
    final source = baseStyle(context);
    final fallback = DefaultTextStyle.of(context).style;
    final baseFontSize = source.fontSize ?? fallback.fontSize;
    final baseColor =
        source.color ??
        fallback.color ??
        Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // Lay out the complete line at the reader's chosen size once. Scaling
      // only when necessary avoids iterative font-size measurement and keeps
      // both the painted line and its layout height within the available box.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text.replaceAll(_whitespace, ' ').trim(),
          key: const Key('forum-html-discuz-edit-status'),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: source.copyWith(
            fontSize: baseFontSize == null ? null : baseFontSize * 0.88,
            fontStyle: FontStyle.italic,
            color: baseColor.withValues(alpha: 0.62),
          ),
        ),
      ),
    );
  }
}
