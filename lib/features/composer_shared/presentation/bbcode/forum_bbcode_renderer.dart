import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bbcode/flutter_bbcode.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_collapse_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attachment_preview_resolvers.dart';
import 'package:y300/features/composer_shared/domain/services/composer_collapse_document_parser.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_tokenizer.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_bbcode_tokenizer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_attachment_preview.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/discuz_font_size_policy.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_collapse_chrome.dart';

typedef ForumAttachPreviewImageBuilder = ComposerLocalImageBuilder;
typedef ForumAttachPreviewFileExists = ComposerLocalFileExists;
typedef ForumStickerPreviewImageBuilder =
    Widget Function(StickerItem sticker, Key key);

Widget _defaultAttachPreviewImageBuilder(File file, Key key) {
  return defaultComposerLocalImageBuilder(file, key);
}

bool _defaultAttachPreviewFileExists(File file) {
  return defaultComposerLocalFileExists(file);
}

Widget _defaultStickerPreviewImageBuilder(StickerItem sticker, Key key) {
  return ComposerStickerImage(
    sticker: sticker,
    key: key,
    fit: BoxFit.contain,
    placeholder: const SizedBox.shrink(),
    errorPlaceholder: const Icon(Icons.broken_image_outlined),
  );
}

/// 论坛 BBCode 渲染契约。把 Discuz 常用扩展、表情码与 `[attach]aid[/attach]`
/// 转成可读预览，其余 tag 走 [flutter_bbcode] 默认实现。
abstract class ForumBbCodeRenderer {
  const ForumBbCodeRenderer();

  Widget buildPreview(
    BuildContext context,
    String source, {
    List<StickerItem> stickers = const [],
    List<ComposerImageAttachment> imageAttachments =
        const <ComposerImageAttachment>[],
    ComposerAttachmentPreviewResolver? attachmentResolver,
  });
}

class FlutterBbCodeForumRenderer extends ForumBbCodeRenderer {
  const FlutterBbCodeForumRenderer({
    this.stickerTokenizer = const StickerBbCodeTokenizer(),
    this.attachTokenizer = const ComposerAttachBbCodeTokenizer(),
    this.attachImageBuilder = _defaultAttachPreviewImageBuilder,
    this.attachFileExists = _defaultAttachPreviewFileExists,
    this.stickerImageBuilder = _defaultStickerPreviewImageBuilder,
  });

  final StickerBbCodeTokenizer stickerTokenizer;
  final ComposerAttachBbCodeTokenizer attachTokenizer;
  final ForumAttachPreviewImageBuilder attachImageBuilder;
  final ForumAttachPreviewFileExists attachFileExists;
  final ForumStickerPreviewImageBuilder stickerImageBuilder;
  static const _collapseParser = ComposerCollapseDocumentParser();

  @override
  Widget buildPreview(
    BuildContext context,
    String source, {
    List<StickerItem> stickers = const [],
    List<ComposerImageAttachment> imageAttachments =
        const <ComposerImageAttachment>[],
    ComposerAttachmentPreviewResolver? attachmentResolver,
  }) {
    final collapseDocument = _collapseParser.parse(source);
    if (collapseDocument.hasCollapse) {
      return _CollapsePreviewDocument(
        document: collapseDocument,
        renderer: this,
        stickers: stickers,
        imageAttachments: imageAttachments,
        attachmentResolver: attachmentResolver,
        sourceId: 'composer-collapse-${_stableHash(source)}',
      );
    }
    return _buildBasePreview(
      context,
      source,
      stickers: stickers,
      imageAttachments: imageAttachments,
      attachmentResolver: attachmentResolver,
    );
  }

  Widget _buildBasePreview(
    BuildContext context,
    String source, {
    List<StickerItem> stickers = const [],
    List<ComposerImageAttachment> imageAttachments =
        const <ComposerImageAttachment>[],
    ComposerAttachmentPreviewResolver? attachmentResolver,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle =
        Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface) ??
        TextStyle(color: colorScheme.onSurface);
    final stickerEncoded = stickerTokenizer.encodeForPreview(source, stickers);
    final resolver =
        attachmentResolver ??
        UploadedComposerAttachmentPreviewResolver(
          imageAttachments: imageAttachments,
        );
    final previewSource = attachTokenizer.encodeForPreviewWithResolver(
      stickerEncoded,
      resolver,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxImageWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 520.0;
        final stylesheet = defaultBBStylesheet(textStyle: textStyle);
        stylesheet.removeTag('img');
        stylesheet.addTag(_BackColorTag());
        stylesheet.addTag(_DiscuzSizeTag(textStyle.fontSize ?? 14));
        stylesheet.addTag(_DiscuzCodeTag(colorScheme, textStyle));
        stylesheet.addTag(_DiscuzAlignTag());
        stylesheet.addTag(_StickerPreviewTag(stickers, stickerImageBuilder));
        stylesheet.addTag(
          _AttachSourceFallbackTag(ComposerAttachTagKind.attach),
        );
        stylesheet.addTag(
          _AttachSourceFallbackTag(ComposerAttachTagKind.attachImg),
        );
        stylesheet.addTag(
          _AttachPreviewTag(
            resolver,
            maxImageWidth,
            attachImageBuilder,
            attachFileExists,
            ComposerAttachBbCodeTokenizer.previewTag,
            ComposerAttachTagKind.attach,
          ),
        );
        stylesheet.addTag(
          _AttachPreviewTag(
            resolver,
            maxImageWidth,
            attachImageBuilder,
            attachFileExists,
            ComposerAttachBbCodeTokenizer.previewAttachImgTag,
            ComposerAttachTagKind.attachImg,
          ),
        );

        return BBCodeText(
          data: previewSource,
          stylesheet: stylesheet,
          errorBuilder: (_, _, _) => Text(source, style: textStyle),
        );
      },
    );
  }
}

class _CollapsePreviewDocument extends StatelessWidget {
  const _CollapsePreviewDocument({
    required this.document,
    required this.renderer,
    required this.stickers,
    required this.imageAttachments,
    required this.attachmentResolver,
    required this.sourceId,
  });

  final ComposerCollapseDocument document;
  final FlutterBbCodeForumRenderer renderer;
  final List<StickerItem> stickers;
  final List<ComposerImageAttachment> imageAttachments;
  final ComposerAttachmentPreviewResolver? attachmentResolver;
  final String sourceId;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key(sourceId),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < document.parts.length; index += 1)
          _buildPart(context, document.parts[index], index),
      ],
    );
  }

  Widget _buildPart(
    BuildContext context,
    ComposerCollapsePart part,
    int index,
  ) {
    final localizations = AppLocalizations.of(context);
    switch (part) {
      case ComposerCollapseText(:final value):
        if (value.isEmpty) {
          return const SizedBox.shrink();
        }
        return renderer._buildBasePreview(
          context,
          value,
          stickers: stickers,
          imageAttachments: imageAttachments,
          attachmentResolver: attachmentResolver,
        );
      case ComposerCollapseBlock(:final id, :final title, :final body):
        return ForumCollapseChrome(
          sourceId: '$sourceId-$index-$id',
          initiallyExpanded: false,
          title: renderer._buildBasePreview(
            context,
            title,
            stickers: stickers,
            imageAttachments: imageAttachments,
            attachmentResolver: attachmentResolver,
          ),
          contentBuilder: (_) => renderer.buildPreview(
            context,
            body.source,
            stickers: stickers,
            imageAttachments: imageAttachments,
            attachmentResolver: attachmentResolver,
          ),
          expandedSemanticsLabel: localizations.threadHtmlCollapseExpanded,
          collapsedSemanticsLabel: localizations.threadHtmlCollapseCollapsed,
        );
    }
  }
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

class _BackColorTag extends StyleTag {
  _BackColorTag() : super('backcolor');

  @override
  TextStyle transformStyle(
    TextStyle oldStyle,
    Map<String, String>? attributes,
  ) {
    final color = _parseBbCodeColor(_firstAttributeValue(attributes));
    return color == null ? oldStyle : oldStyle.copyWith(backgroundColor: color);
  }
}

class _DiscuzSizeTag extends StyleTag {
  _DiscuzSizeTag(this.baseFontSize) : super('size');

  final double baseFontSize;

  @override
  TextStyle transformStyle(
    TextStyle oldStyle,
    Map<String, String>? attributes,
  ) {
    final rawSize = int.tryParse(_firstAttributeValue(attributes) ?? '');
    final size =
        DiscuzFontSizePolicy.normalize(rawSize) ??
        DiscuzFontSizePolicy.normalSize;
    final fontSize = DiscuzFontSizePolicy.fontSizeForBase(
      size,
      baseFontSize: baseFontSize,
    );
    return fontSize == null ? oldStyle : oldStyle.copyWith(fontSize: fontSize);
  }
}

class _DiscuzCodeTag extends AdvancedTag {
  _DiscuzCodeTag(this.colorScheme, this.baseTextStyle) : super('code');

  final ColorScheme colorScheme;
  final TextStyle baseTextStyle;

  @override
  List<InlineSpan> parse(FlutterRenderer renderer, Object element) {
    final code = _rawBbCodeChildren(element);
    final codeStyle = baseTextStyle.copyWith(
      color: colorScheme.onSurface,
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Consolas', 'Courier New'],
    );
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: Container(
          key: const Key('reply-bbcode-preview-code-block'),
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(code, style: codeStyle),
        ),
      ),
    ];
  }
}

String _rawBbCodeChildren(Object element) {
  final children = (element as dynamic).children as Iterable<dynamic>;
  return children.map((child) => _rawBbCodeNode(child)).join();
}

String _rawBbCodeNode(dynamic node) {
  final tag = _dynamicString(node, 'tag');
  if (tag == null) {
    return _dynamicString(node, 'text') ??
        _dynamicString(node, 'textContent') ??
        '';
  }
  final attributes = (node as dynamic).attributes as Map<String, String>?;
  final children = (node as dynamic).children as Iterable<dynamic>;
  final serializedAttributes = _serializeRawBbCodeAttributes(attributes);
  return '[$tag$serializedAttributes]'
      '${children.map((child) => _rawBbCodeNode(child)).join()}'
      '[/$tag]';
}

String? _dynamicString(dynamic node, String propertyName) {
  try {
    final value = switch (propertyName) {
      'tag' => (node as dynamic).tag,
      'text' => (node as dynamic).text,
      'textContent' => (node as dynamic).textContent,
      _ => null,
    };
    return value is String ? value : null;
  } on Object {
    return null;
  }
}

String _serializeRawBbCodeAttributes(Map<String, String>? attributes) {
  if (attributes == null || attributes.isEmpty) {
    return '';
  }
  if (attributes.length == 1) {
    final entry = attributes.entries.single;
    if (entry.key == entry.value || entry.key.isEmpty) {
      return '=${entry.value}';
    }
  }
  return attributes.entries.map((entry) {
    if (entry.value.isEmpty || entry.key == entry.value) {
      return ' ${entry.key}';
    }
    return ' ${entry.key}=${entry.value}';
  }).join();
}

class _DiscuzAlignTag extends WrappedStyleTag {
  _DiscuzAlignTag() : super('align');

  @override
  List<InlineSpan> wrap(
    FlutterRenderer renderer,
    Object element,
    List<InlineSpan> spans,
  ) {
    final textAlign = switch (_firstAttributeValue(
      (element as dynamic).attributes as Map<String, String>?,
    )?.toLowerCase()) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: SizedBox(
          key: Key('reply-bbcode-preview-align-${textAlign.name}'),
          width: double.infinity,
          child: RichText(
            textAlign: textAlign,
            text: TextSpan(children: spans),
          ),
        ),
      ),
    ];
  }
}

class _AttachPreviewTag extends WrappedStyleTag {
  _AttachPreviewTag(
    this.resolver,
    this.maxImageWidth,
    this.attachImageBuilder,
    this.attachFileExists,
    String tagName,
    this.tagKind,
  ) : super(tagName);

  final ComposerAttachmentPreviewResolver resolver;
  final double maxImageWidth;
  final ForumAttachPreviewImageBuilder attachImageBuilder;
  final ForumAttachPreviewFileExists attachFileExists;
  final ComposerAttachTagKind tagKind;

  @override
  List<InlineSpan> wrap(
    FlutterRenderer renderer,
    Object element,
    List<InlineSpan> spans,
  ) {
    final children = (element as dynamic).children as Iterable<dynamic>;
    final aid = children
        .map((child) => child.textContent as String)
        .join()
        .trim();
    final resolution = resolver.resolve(aid);
    if (!resolution.isAvailable) {
      return _attachTextFallback(renderer, aid, tagKind);
    }
    final preview = resolution.preview;
    if (preview is ComposerLocalImagePreview &&
        !attachFileExists(File(preview.path))) {
      return const <InlineSpan>[];
    }

    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxImageWidth),
          child: ComposerAttachmentPreviewImage(
            key: Key('reply-bbcode-preview-attach-preview-$aid'),
            resolution: resolution,
            maxWidth: maxImageWidth,
            imageKey: Key('reply-bbcode-preview-attach-$aid'),
            localImageBuilder: attachImageBuilder,
            localFileExists: attachFileExists,
          ),
        ),
      ),
    ];
  }
}

String? _firstAttributeValue(Map<String, String>? attributes) {
  if (attributes == null || attributes.isEmpty) {
    return null;
  }
  for (final value in attributes.values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  for (final key in attributes.keys) {
    final trimmed = key.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

Color? _parseBbCodeColor(String? rawColor) {
  if (rawColor == null) {
    return null;
  }
  final match = RegExp(
    r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$',
  ).firstMatch(rawColor.trim());
  if (match == null) {
    return null;
  }
  final hex = match.group(1)!;
  final expanded = hex.length == 3
      ? hex.split('').map((digit) => '$digit$digit').join()
      : hex;
  return Color(int.parse('ff$expanded', radix: 16));
}

class _AttachSourceFallbackTag extends WrappedStyleTag {
  _AttachSourceFallbackTag(this.kind) : super(kind.wireName);

  final ComposerAttachTagKind kind;

  @override
  List<InlineSpan> wrap(
    FlutterRenderer renderer,
    Object element,
    List<InlineSpan> spans,
  ) {
    final children = (element as dynamic).children as Iterable<dynamic>;
    final aid = children
        .map((child) => child.textContent as String)
        .join()
        .trim();
    return _attachTextFallback(renderer, aid, kind);
  }
}

List<InlineSpan> _attachTextFallback(
  FlutterRenderer renderer,
  String aid,
  ComposerAttachTagKind kind,
) {
  return [
    TextSpan(
      text: '[${kind.wireName}]$aid[/${kind.wireName}]',
      style: renderer.getCurrentStyle(),
    ),
  ];
}

class _StickerPreviewTag extends WrappedStyleTag {
  _StickerPreviewTag(List<StickerItem> stickers, this.stickerImageBuilder)
    : _stickersByCode = {for (final sticker in stickers) sticker.code: sticker},
      super(StickerBbCodeTokenizer.previewTag);

  final Map<String, StickerItem> _stickersByCode;
  final ForumStickerPreviewImageBuilder stickerImageBuilder;

  @override
  List<InlineSpan> wrap(
    FlutterRenderer renderer,
    Object element,
    List<InlineSpan> spans,
  ) {
    final children = (element as dynamic).children as Iterable<dynamic>;
    final code = children.map((child) => child.textContent as String).join();
    final sticker = _stickersByCode[code];
    if (sticker == null) {
      return spans.isEmpty
          ? [TextSpan(text: code, style: renderer.getCurrentStyle())]
          : spans;
    }
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: stickerImageBuilder(
          sticker,
          Key('reply-bbcode-preview-sticker-${sticker.code}'),
        ),
      ),
    ];
  }
}
