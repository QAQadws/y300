import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import '../models/forum_html_content_layout.dart';
import '../models/forum_html_render_options.dart';
import '../contracts/forum_html_collapse_labels.dart';
import '../contracts/forum_html_image_host.dart';
import '../services/forum_html_body_presentation.dart';
import '../services/forum_html_image_viewport_coordinator.dart';
import '../services/forum_html_image_anchor_controller.dart';
import 'forum_html_image_widget_factory.dart';
import 'forum_html_block_decorator.dart';
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
    this.imageAnchorController,
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
    this.hasTrailingContent = false,
    this.blockDecorator,
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
  final ForumHtmlImageAnchorController? imageAnchorController;
  final bool? buildAsync;
  final bool? enableCaching;
  final RenderMode renderMode;
  final VoidCallback? onBodyBuilt;
  final ForumHtmlBodyPresentation? bodyPresentation;

  /// Owner-supplied mutable expansion memory. Built folds record their effective
  /// defaults so a host can track changes to the currently visible layout.
  final Map<String, bool>? collapseExpansion;
  final String? sourceId;
  final ForumHtmlBlockSpacingMode blockSpacingMode;
  final Uri? linkBaseUri;
  final ForumHtmlContentLayout contentLayout;

  /// True for a display fragment before the logical body's final content edge.
  final bool hasTrailingContent;
  final ForumHtmlBlockDecorator? blockDecorator;

  @override
  State<ForumHtmlRenderer> createState() => _ForumHtmlRendererState();
}

class _ForumHtmlRendererState extends State<ForumHtmlRenderer> {
  final _inlineLayoutPresentation = ForumHtmlBodyPresentation();
  late final _binding = ValueNotifier<ForumHtmlImageFactoryBinding>((
    host: widget.imageHost,
    viewport: widget.imageViewportCoordinator,
    handlesImageTap: widget.callbacks.onTapImage != null,
    imageAnchors: widget.imageAnchorController,
    imageAnchorRevision: widget.imageAnchorController?.bindingIdentity,
    sourceId: widget.preparedDocument.sequence.sourceId,
  ));
  // Cached custom widgets subscribe only to values that affect their output.
  // A stable callback view lets nested bodies read current nullable handlers.
  late final _foldLayout = ValueNotifier(_foldLayoutValue);
  late final _collapseLabels = ValueNotifier(widget.labels);
  late final _blockDecoration = ValueNotifier(widget.blockDecorator);
  late final _foldUpdates = Listenable.merge([_foldLayout, _collapseLabels]);
  late final _liveCallbacks = _CurrentRenderCallbacks(() => widget.callbacks);

  _FoldLayoutValue get _foldLayoutValue => _FoldLayoutValue((
    widget.options,
    widget.textStyle,
    widget.textAlign,
    widget.theme.signature,
    widget.bodyPresentation,
    widget.buildAsync,
    widget.enableCaching,
    widget.blockSpacingMode,
    widget.contentLayout,
    widget.linkBaseUri,
  ), widget.collapseExpansion);
  VoidCallback? _onReady;
  HtmlWidget? _htmlBody;
  Object? _htmlBodyIdentity;

  @override
  void initState() {
    super.initState();
    widget.imageAnchorController?.bindSequence(
      widget.preparedDocument.sequence,
    );
    _binding.value = (
      host: widget.imageHost,
      viewport: widget.imageViewportCoordinator,
      handlesImageTap: widget.callbacks.onTapImage != null,
      imageAnchors: widget.imageAnchorController,
      imageAnchorRevision: widget.imageAnchorController?.bindingIdentity,
      sourceId: widget.preparedDocument.sequence.sourceId,
    );
  }

  @override
  void didUpdateWidget(covariant ForumHtmlRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.imageAnchorController?.bindSequence(
      widget.preparedDocument.sequence,
    );
    final hostChanged =
        (oldWidget.imageHostRevision ?? oldWidget.imageHost) !=
        (widget.imageHostRevision ?? widget.imageHost);
    if (hostChanged ||
        (oldWidget.callbacks.onTapImage == null) !=
            (widget.callbacks.onTapImage == null) ||
        !identical(
          oldWidget.imageViewportCoordinator,
          widget.imageViewportCoordinator,
        ) ||
        !identical(
          oldWidget.imageAnchorController,
          widget.imageAnchorController,
        ) ||
        !identical(
          _binding.value.imageAnchorRevision,
          widget.imageAnchorController?.bindingIdentity,
        ) ||
        _binding.value.sourceId != widget.preparedDocument.sequence.sourceId) {
      _binding.value = (
        host: hostChanged ? widget.imageHost : _binding.value.host,
        viewport: widget.imageViewportCoordinator,
        handlesImageTap: widget.callbacks.onTapImage != null,
        imageAnchors: widget.imageAnchorController,
        imageAnchorRevision: widget.imageAnchorController?.bindingIdentity,
        sourceId: widget.preparedDocument.sequence.sourceId,
      );
    }
    _foldLayout.value = _foldLayoutValue;
    _collapseLabels.value = widget.labels;
    _blockDecoration.value = widget.blockDecorator;
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
      hasTrailingContent: widget.hasTrailingContent,
    );
    final binding =
        context
            .getInheritedWidgetOfExactType<_ForumHtmlInheritedHostBinding>()
            ?.binding ??
        _binding;
    final baseStyle = widget.textStyle ?? stylePolicy.baseTextStyle(context);
    Widget buildBody(VoidCallback? ready) {
      _onReady = ready;
      final identity = (
        document.preparedHtml,
        baseStyle,
        widget.options,
        widget.textStyle,
        widget.textAlign,
        widget.theme.signature,
        widget.blockSpacingMode,
        widget.contentLayout,
        widget.hasTrailingContent,
        widget.linkBaseUri,
        widget.buildAsync,
        widget.enableCaching,
        widget.renderMode,
        widget.sourceId,
        widget.blockDecorator != null,
        binding,
      );
      // Keep the mounted HtmlWidget input stable too: fwfh's cached root
      // placeholders otherwise rebuild even when no configuration was emitted.
      if (_htmlBodyIdentity != identity) {
        _htmlBodyIdentity = identity;
        _htmlBody = HtmlWidget(
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
            decorateBlock: _decorateBlock,
            blockDecorationEnabled: () => widget.blockDecorator != null,
            bodyPresentationFor: () =>
                widget.bodyPresentation ?? _inlineLayoutPresentation,
            hasTrailingContentFor: () => widget.hasTrailingContent,
            textAlignFor: () => widget.textAlign,
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
            widget.hasTrailingContent,
            widget.linkBaseUri,
            widget.blockDecorator != null,
          ],
          textStyle: baseStyle,
          onTapUrl: (url) {
            final callback = widget.callbacks.onTapUrl;
            if (callback == null) return false;
            widget.callbacks.onInteraction?.call();
            return callback(url);
          },
        );
      }
      // fwfh retains its factory and root properties. An alignment-only change
      // must invalidate inherited root properties without remounting the body.
      return DefaultTextStyle.merge(
        textAlign: widget.textAlign ?? TextAlign.start,
        child: _htmlBody!,
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
      widget.hasTrailingContent,
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
      final child = _DiscuzEditStatusText(
        text: element.text.trim(),
        baseStyle: (context) =>
            widget.textStyle ?? stylePolicy.baseTextStyle(context),
      );
      return _decorateCustomBlock(element, child);
    }
    if (!stylePolicy.isForumCollapseElement(element)) return null;
    final collapseId = _collapseSourceId(element);
    final initiallyExpanded =
        widget.collapseExpansion?.putIfAbsent(
          collapseId,
          () => stylePolicy.isForumCollapseInitiallyExpanded(element),
        ) ??
        stylePolicy.isForumCollapseInitiallyExpanded(element);
    final titleHtml = _firstChildWithClass(
      element,
      'showcollapse_title',
    )?.innerHtml;
    final contentHtml = _DeferredCollapseContentHtml(
      _firstChildWithClass(element, 'showcollapse_content'),
    );
    return _decorateCustomBlock(
      element,
      ListenableBuilder(
        listenable: _foldUpdates,
        builder: (context, _) => ForumCollapseBlock.lazyContent(
          titleHtml:
              titleHtml ??
              const HtmlEscape().convert(widget.labels.fallbackTitle),
          contentHtmlBuilder: contentHtml.call,
          labels: widget.labels,
          initiallyExpanded:
              widget.collapseExpansion?[collapseId] ?? initiallyExpanded,
          onExpandedChanged: (expanded) =>
              widget.collapseExpansion?[collapseId] = expanded,
          sourceId: collapseId,
          onInteraction: () => widget.callbacks.onInteraction?.call(),
          nestedRendererBuilder: (html, {required sourceId}) =>
              _ForumHtmlInheritedHostBinding(
                binding: binding,
                child: ForumHtmlRenderer(
                  preparedDocument: document.copyWith(preparedHtml: html),
                  theme: widget.theme,
                  options: widget.options,
                  textStyle: widget.textStyle,
                  textAlign: widget.textAlign,
                  labels: widget.labels,
                  callbacks: _liveCallbacks,
                  collapseExpansion: widget.collapseExpansion,
                  bodyPresentation: widget.bodyPresentation,
                  buildAsync: widget.buildAsync,
                  enableCaching: widget.enableCaching,
                  sourceId: sourceId,
                  blockSpacingMode: widget.blockSpacingMode,
                  contentLayout: widget.contentLayout,
                  linkBaseUri: widget.linkBaseUri,
                ),
              ),
        ),
      ),
    );
  }

  Widget _decorateCustomBlock(html_dom.Element element, Widget child) =>
      widget.blockDecorator == null ||
          ForumHtmlBlockDecorationPolicy.hasBlockAncestor(element)
      ? child
      : _decorateBlock(child);

  Widget _decorateBlock(Widget child) =>
      ValueListenableBuilder<ForumHtmlBlockDecorator?>(
        valueListenable: _blockDecoration,
        child: child,
        builder: (context, decorate, retainedChild) =>
            decorate?.call(context, retainedChild!) ?? retainedChild!,
      );

  @override
  void dispose() {
    _inlineLayoutPresentation.dispose();
    _binding.dispose();
    _foldLayout.dispose();
    _collapseLabels.dispose();
    _blockDecoration.dispose();
    super.dispose();
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
}

/// Expansion maps are mutable Host-owned state. Snapshot their values so a
/// same-map edit is observed, while equal recreated layout values stay quiet.
final class _FoldLayoutValue {
  _FoldLayoutValue(this.layout, this.expansionOwner)
    : expansion = Map<String, bool>.of(expansionOwner ?? const {});

  final Object layout;
  final Map<String, bool>? expansionOwner;
  final Map<String, bool> expansion;

  @override
  bool operator ==(Object other) =>
      other is _FoldLayoutValue &&
      layout == other.layout &&
      identical(expansionOwner, other.expansionOwner) &&
      mapEquals(expansion, other.expansion);

  @override
  int get hashCode => Object.hash(
    layout,
    identityHashCode(expansionOwner),
    Object.hashAllUnordered(
      expansion.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Keeps current handler nullability as well as dispatch. An absent URL
/// handler must not start interaction tracking merely because it is nested.
final class _CurrentRenderCallbacks extends ForumHtmlRenderCallbacks {
  const _CurrentRenderCallbacks(this._current);
  final ValueGetter<ForumHtmlRenderCallbacks> _current;

  @override
  VoidCallback? get onInteraction => _current().onInteraction;
  @override
  FutureOr<bool> Function(String url)? get onTapUrl => _current().onTapUrl;
  @override
  void Function(ForumHtmlImageRequest request)? get onTapImage =>
      _current().onTapImage;
  @override
  void Function(ForumHtmlImageLayoutShift shift)? get onImageLayoutShift =>
      _current().onImageLayoutShift;
}

// Each fwfh custom fragment owns this source: configuration updates share it,
// while rebuilding different HTML creates a fresh source. Only its extracted
// string survives the first expansion; it never retains Context or a Widget.
final class _DeferredCollapseContentHtml {
  _DeferredCollapseContentHtml(this._content);

  html_dom.Element? _content;
  String? _html;

  String call() {
    final cached = _html;
    if (cached != null) return cached;
    final content = _content;
    final String html;
    if (content == null) {
      html = '';
    } else {
      final clone = html_parser.parseFragment(content.innerHtml);
      for (final gather in clone.querySelectorAll('.showcollapse_gather')) {
        gather.remove();
      }
      html = clone.nodes.map(_serializeNode).join();
    }
    _content = null;
    return _html = html;
  }

  static String _serializeNode(html_dom.Node node) {
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
