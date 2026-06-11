import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';

/// BBCode 预览面板：源码模式与预览模式切换的"右半侧"。
class BbCodePreviewPanel extends StatelessWidget {
  const BbCodePreviewPanel({
    super.key,
    required this.source,
    required this.renderer,
    this.stickers = const [],
    this.imageAttachments = const <ComposerImageAttachment>[],
  });

  final String source;
  final ForumBbCodeRenderer renderer;
  final List<StickerItem> stickers;
  final List<ComposerImageAttachment> imageAttachments;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const Key('reply-composer-bbcode-preview-panel'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: source.trim().isEmpty
          ? const SizedBox(
              key: Key('reply-composer-bbcode-preview-empty'),
              height: 24,
            )
          : renderer.buildPreview(
              context,
              source,
              stickers: stickers,
              imageAttachments: imageAttachments,
            ),
    );
  }
}
