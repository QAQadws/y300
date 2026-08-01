import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_source_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_toolbar_action.dart';

/// Shared source/Quill editor surface composition.
///
/// Feature pages keep ownership of their scaffold and business state. This
/// widget only wires the same message, resolver, insertion callback and
/// toolbar extension into either editor surface.
class ComposerMessageEditorSurface extends StatelessWidget {
  const ComposerMessageEditorSurface({
    super.key,
    required this.surface,
    required this.message,
    required this.sourceController,
    required this.enabled,
    required this.bbCodeRenderer,
    required this.stickerGroups,
    required this.initialStickerGroupId,
    required this.onStickerGroupChanged,
    required this.onMessageChanged,
    this.imageAttachments = const <ComposerImageAttachment>[],
    this.attachmentResolver,
    this.messageRevision = 0,
    this.lastMessageMutation,
    this.onImagePressed,
    this.stickers = const <StickerItem>[],
    this.keyPrefix = 'composer',
    this.hintText,
    this.expand = true,
    this.extraToolbarActions = const <ComposerToolbarAction>[],
  });

  final ComposerSurfacePreference surface;
  final String message;
  final TextEditingController sourceController;
  final bool enabled;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerGroup> stickerGroups;
  final List<StickerItem> stickers;
  final String? initialStickerGroupId;
  final ValueChanged<String> onStickerGroupChanged;
  final ValueChanged<String> onMessageChanged;
  final List<ComposerImageAttachment> imageAttachments;
  final ComposerAttachmentPreviewResolver? attachmentResolver;
  final int messageRevision;
  final ComposerTextMutation? lastMessageMutation;
  final ComposerImageInsertCallback? onImagePressed;
  final String keyPrefix;
  final String? hintText;
  final bool expand;
  final List<ComposerToolbarAction> extraToolbarActions;

  @override
  Widget build(BuildContext context) {
    final renderer = bbCodeRenderer;
    final localImageBuilder = renderer is FlutterBbCodeForumRenderer
        ? renderer.attachImageBuilder
        : null;
    final localFileExists = renderer is FlutterBbCodeForumRenderer
        ? renderer.attachFileExists
        : null;
    return switch (surface) {
      ComposerSurfacePreference.quill => ComposerQuillEditorSurface(
        key: Key('$keyPrefix-quill-editor'),
        keyPrefix: keyPrefix,
        bbCode: message,
        enabled: enabled,
        stickers: stickers,
        stickerGroups: stickerGroups,
        initialStickerGroupId: initialStickerGroupId,
        onStickerGroupChanged: onStickerGroupChanged,
        imageAttachments: imageAttachments,
        attachmentResolver: attachmentResolver,
        attachImageBuilder: localImageBuilder,
        attachFileExists: localFileExists,
        hintText: hintText,
        expand: expand,
        onBbCodeChanged: onMessageChanged,
        messageRevision: messageRevision,
        lastMessageMutation: lastMessageMutation,
        onImagePressed: onImagePressed,
        extraToolbarActions: extraToolbarActions,
      ),
      ComposerSurfacePreference.source => ComposerBbCodeSourceEditor(
        keyPrefix: keyPrefix,
        viewKey: Key('$keyPrefix-source-view'),
        inputKey: Key('$keyPrefix-message-input'),
        controller: sourceController,
        enabled: enabled,
        messageRevision: messageRevision,
        onImagePressed: onImagePressed,
        hintText: hintText,
        onChanged: onMessageChanged,
        extraToolbarActions: extraToolbarActions,
      ),
    };
  }
}
