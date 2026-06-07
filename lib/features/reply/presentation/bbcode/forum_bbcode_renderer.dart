import 'package:flutter/material.dart';
import 'package:flutter_bbcode/flutter_bbcode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/sticker_bbcode_tokenizer.dart';

final forumBbCodeRendererProvider = Provider<ForumBbCodeRenderer>((ref) {
  return FlutterBbCodeForumRenderer(
    tokenizer: ref.read(stickerBbCodeTokenizerProvider),
  );
});

abstract class ForumBbCodeRenderer {
  const ForumBbCodeRenderer();

  Widget buildPreview(
    BuildContext context,
    String source, {
    List<StickerItem> stickers = const [],
  });
}

class FlutterBbCodeForumRenderer extends ForumBbCodeRenderer {
  const FlutterBbCodeForumRenderer({
    this.tokenizer = const StickerBbCodeTokenizer(),
  });

  final StickerBbCodeTokenizer tokenizer;

  @override
  Widget buildPreview(
    BuildContext context,
    String source, {
    List<StickerItem> stickers = const [],
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ) ??
        TextStyle(color: colorScheme.onSurface);
    final stylesheet = defaultBBStylesheet(textStyle: textStyle);
    stylesheet.removeTag('img');
    stylesheet.addTag(_StickerPreviewTag(stickers));

    return BBCodeText(
      data: tokenizer.encodeForPreview(source, stickers),
      stylesheet: stylesheet,
      errorBuilder: (_, _, _) => Text(source, style: textStyle),
    );
  }
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
        alignment: PlaceholderAlignment.middle,
        child: Image.asset(
          sticker.assetPath,
          key: Key('reply-bbcode-preview-sticker-${sticker.code}'),
          width: 28,
          height: 28,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            size: 28,
          ),
        ),
      ),
    ];
  }
}
