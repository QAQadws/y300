import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';

/// BBCode 预览面板。
class BbCodePreviewPanel extends StatelessWidget {
  const BbCodePreviewPanel({
    super.key,
    required this.source,
    required this.renderer,
    this.stickers = const [],
    this.imageAttachments = const <ComposerImageAttachment>[],
    this.panelKey = const Key('reply-composer-bbcode-preview-panel'),
    this.emptyKey = const Key('reply-composer-bbcode-preview-empty'),
  });

  final String source;
  final ForumBbCodeRenderer renderer;
  final List<StickerItem> stickers;
  final List<ComposerImageAttachment> imageAttachments;
  final Key panelKey;
  final Key emptyKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: panelKey,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 24),
      child: source.trim().isEmpty
          ? SizedBox(key: emptyKey, height: 24)
          : renderer.buildPreview(
              context,
              source,
              stickers: stickers,
              imageAttachments: imageAttachments,
            ),
    );
  }
}
