import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/bbcode_preview_panel.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_context_menu.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 同屏编辑与预览，避免在源码/预览之间来回切换。
class ComposerEditorPreview extends StatelessWidget {
  const ComposerEditorPreview({
    super.key,
    required this.inputKey,
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.onChanged,
    required this.renderer,
    this.stickers = const <StickerItem>[],
    this.imageAttachments = const <ComposerImageAttachment>[],
    this.attachmentResolver,
    this.previewPanelKey = const Key('reply-composer-bbcode-preview-panel'),
    this.previewEmptyKey = const Key('reply-composer-bbcode-preview-empty'),
    this.previewLabelKey,
    this.minLines = 8,
  });

  final Key inputKey;
  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ForumBbCodeRenderer renderer;
  final List<StickerItem> stickers;
  final List<ComposerImageAttachment> imageAttachments;
  final ComposerAttachmentPreviewResolver? attachmentResolver;
  final Key previewPanelKey;
  final Key previewEmptyKey;
  final Key? previewLabelKey;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: inputKey,
          controller: controller,
          enabled: enabled,
          minLines: minLines,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          onChanged: onChanged,
          contextMenuBuilder: ComposerBbCodeContextMenu.build,
          decoration: InputDecoration(
            hintText: hintText,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context).composerPreview,
          key: previewLabelKey,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        BbCodePreviewPanel(
          source: controller.text,
          renderer: renderer,
          stickers: stickers,
          imageAttachments: imageAttachments,
          attachmentResolver: attachmentResolver,
          panelKey: previewPanelKey,
          emptyKey: previewEmptyKey,
        ),
      ],
    );
  }
}
