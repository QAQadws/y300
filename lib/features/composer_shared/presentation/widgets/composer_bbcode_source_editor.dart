import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_context_menu.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_toolbar.dart';
import 'package:y300/features/composer_shared/presentation/widgets/sticker_picker_sheet.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComposerBbCodeSourceEditor extends StatelessWidget {
  const ComposerBbCodeSourceEditor({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.messageRevision = 0,
    this.onImagePressed,
    this.keyPrefix = 'composer-source',
    this.viewKey,
    this.inputKey,
    this.hintText,
    this.minLines = 12,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: ForumContentSpacing.composerSourceEditorHorizontal,
    ),
  });

  static const _insertionService = ComposerBbCodeInsertionService();
  static InputDecoration noBorderDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      filled: false,
      isCollapsed: true,
    );
  }

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final int messageRevision;
  final ComposerImageInsertCallback? onImagePressed;
  final String keyPrefix;
  final Key? viewKey;
  final Key? inputKey;
  final String? hintText;
  final int minLines;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: viewKey ?? Key('$keyPrefix-view'),
      padding: contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ComposerBbCodeToolbar(
            keyPrefix: keyPrefix,
            enabled: enabled,
            onStickerPressed: () {
              _pickSticker(context);
            },
            onCommandSelected: _insertCommand,
            onImagePressed: onImagePressed == null
                ? null
                : () {
                    unawaited(_pickImage());
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            key: inputKey ?? Key('$keyPrefix-input'),
            controller: controller,
            enabled: enabled,
            minLines: minLines,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            contextMenuBuilder: ComposerBbCodeContextMenu.build,
            onChanged: onChanged,
            decoration: noBorderDecoration(
              hintText ?? AppLocalizations.of(context).composerSourceMode,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSticker(BuildContext context) async {
    final sticker = await showModalBottomSheet<StickerItem>(
      context: context,
      builder: (_) => const StickerPickerSheet(),
    );
    if (sticker != null) {
      _insertSticker(sticker);
    }
  }

  Future<void> _pickImage() async {
    final callback = onImagePressed;
    if (callback == null || !enabled) {
      return;
    }
    final selection = controller.selection;
    final textLength = controller.text.length;
    final start = selection.isValid ? selection.start : textLength;
    final end = selection.isValid ? selection.end : textLength;
    await callback(
      ComposerInsertionAnchor(
        baseRevision: messageRevision,
        selection: ComposerSelection(
          start: start.clamp(0, textLength).toInt(),
          end: end.clamp(0, textLength).toInt(),
        ),
        mode: ComposerEditorMode.source,
      ),
    );
  }

  void _insertCommand(ComposerBbCodeCommand command) {
    final nextValue = _insertionService.wrapSelection(
      controller.value,
      command,
    );
    controller.value = nextValue;
    onChanged(nextValue.text);
  }

  void _insertSticker(StickerItem sticker) {
    final value = controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final normalizedStart = start.clamp(0, text.length).toInt();
    final normalizedEnd = end.clamp(0, text.length).toInt();
    final replaceStart = normalizedStart < normalizedEnd
        ? normalizedStart
        : normalizedEnd;
    final replaceEnd = normalizedStart < normalizedEnd
        ? normalizedEnd
        : normalizedStart;
    final nextText = text.replaceRange(replaceStart, replaceEnd, sticker.code);
    final nextOffset = replaceStart + sticker.code.length;
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    onChanged(nextText);
  }
}
