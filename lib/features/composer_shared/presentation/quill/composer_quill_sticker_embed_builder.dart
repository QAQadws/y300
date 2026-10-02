import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';

class ComposerQuillStickerEmbedBuilder extends EmbedBuilder {
  const ComposerQuillStickerEmbedBuilder({
    required this.stickers,
    this.fixedSize,
  });

  final List<StickerItem> stickers;
  final double? fixedSize;

  @override
  String get key => composerQuillStickerEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => node.value.data.toString();

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final code = embedContext.node.value.data.toString();
    final sticker = stickers.cast<StickerItem?>().firstWhere(
      (item) => item?.code == code,
      orElse: () => null,
    );
    final size = fixedSize;
    if (size != null) {
      return Semantics(
        label: code,
        child: SizedBox.square(
          key: Key('composer-quill-sticker-frame-$code'),
          dimension: size,
          child: sticker == null
              ? const Icon(Icons.mood, size: 18)
              : ComposerStickerImage(
                  key: Key('composer-quill-sticker-$code'),
                  sticker: sticker,
                  width: size,
                  height: size,
                  placeholder: const Icon(Icons.mood, size: 18),
                  errorPlaceholder: const Icon(Icons.mood, size: 18),
                ),
        ),
      );
    }
    if (sticker == null) {
      return Text(code);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ConstrainedBox(
        key: Key('composer-quill-sticker-frame-$code'),
        constraints: const BoxConstraints(maxWidth: 96, maxHeight: 96),
        child: ComposerStickerImage(
          key: Key('composer-quill-sticker-$code'),
          sticker: sticker,
          fit: BoxFit.contain,
          placeholder: const SizedBox.shrink(),
          errorPlaceholder: const Icon(Icons.broken_image_outlined, size: 20),
        ),
      ),
    );
  }
}
