import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bbcode/flutter_bbcode.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_tokenizer.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_bbcode_tokenizer.dart';

typedef ForumAttachPreviewImageBuilder = Widget Function(File file, Key key);
typedef ForumAttachPreviewFileExists = bool Function(File file);

Widget _defaultAttachPreviewImageBuilder(File file, Key key) {
  return Image.file(
    file,
    key: key,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

bool _defaultAttachPreviewFileExists(File file) {
  return file.existsSync();
}

/// 论坛 BBCode 渲染契约。把表情码与 `[attach]aid[/attach]` 转成可读图像，
/// 其余 tag 走 [flutter_bbcode] 默认实现。
abstract class ForumBbCodeRenderer {
  const ForumBbCodeRenderer();

  Widget buildPreview(
    BuildContext context,
    String source, {
    List<StickerItem> stickers = const [],
    List<ComposerImageAttachment> imageAttachments =
        const <ComposerImageAttachment>[],
  });
}

class FlutterBbCodeForumRenderer extends ForumBbCodeRenderer {
  const FlutterBbCodeForumRenderer({
    this.stickerTokenizer = const StickerBbCodeTokenizer(),
    this.attachTokenizer = const ComposerAttachBbCodeTokenizer(),
    this.attachImageBuilder = _defaultAttachPreviewImageBuilder,
    this.attachFileExists = _defaultAttachPreviewFileExists,
  });

  final StickerBbCodeTokenizer stickerTokenizer;
  final ComposerAttachBbCodeTokenizer attachTokenizer;
  final ForumAttachPreviewImageBuilder attachImageBuilder;
  final ForumAttachPreviewFileExists attachFileExists;

  @override
  Widget buildPreview(
    BuildContext context,
    String source, {
    List<StickerItem> stickers = const [],
    List<ComposerImageAttachment> imageAttachments =
        const <ComposerImageAttachment>[],
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ) ??
        TextStyle(color: colorScheme.onSurface);
    final stickerEncoded = stickerTokenizer.encodeForPreview(source, stickers);
    final previewSource = attachTokenizer.encodeForPreview(
      stickerEncoded,
      imageAttachments,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxImageWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 520.0;
        final stylesheet = defaultBBStylesheet(textStyle: textStyle);
        stylesheet.removeTag('img');
        stylesheet.addTag(_StickerPreviewTag(stickers));
        stylesheet.addTag(_AttachSourceFallbackTag());
        stylesheet.addTag(
          _AttachPreviewTag(
            imageAttachments,
            maxImageWidth,
            attachImageBuilder,
            attachFileExists,
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

class _AttachPreviewTag extends WrappedStyleTag {
  _AttachPreviewTag(
    List<ComposerImageAttachment> imageAttachments,
    this.maxImageWidth,
    this.attachImageBuilder,
    this.attachFileExists,
  )   : _attachmentsByAid = {
          for (final attachment in imageAttachments)
            if (attachment.canEnterSubmitPayload)
              attachment.aid!.trim(): attachment,
        },
        super(ComposerAttachBbCodeTokenizer.previewTag);

  final Map<String, ComposerImageAttachment> _attachmentsByAid;
  final double maxImageWidth;
  final ForumAttachPreviewImageBuilder attachImageBuilder;
  final ForumAttachPreviewFileExists attachFileExists;

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
    final attachment = _attachmentsByAid[aid];
    if (attachment == null) {
      return _attachTextFallback(renderer, aid);
    }
    final file = File(attachment.previewPath);
    if (!attachFileExists(file)) {
      return const <InlineSpan>[];
    }

    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxImageWidth),
          child: attachImageBuilder(
            file,
            Key('reply-bbcode-preview-attach-$aid'),
          ),
        ),
      ),
    ];
  }
}

class _AttachSourceFallbackTag extends WrappedStyleTag {
  _AttachSourceFallbackTag() : super('attach');

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
    return _attachTextFallback(renderer, aid);
  }
}

List<InlineSpan> _attachTextFallback(FlutterRenderer renderer, String aid) {
  return [
    TextSpan(
      text: '[attach]$aid[/attach]',
      style: renderer.getCurrentStyle(),
    ),
  ];
}

class _StickerPreviewTag extends WrappedStyleTag {
  _StickerPreviewTag(List<StickerItem> stickers)
      : _stickersByCode = {
          for (final sticker in stickers) sticker.code: sticker,
        },
        super(StickerBbCodeTokenizer.previewTag);

  final Map<String, StickerItem> _stickersByCode;

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
        child: Image.asset(
          sticker.assetPath,
          key: Key('reply-bbcode-preview-sticker-${sticker.code}'),
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
          ),
        ),
      ),
    ];
  }
}
