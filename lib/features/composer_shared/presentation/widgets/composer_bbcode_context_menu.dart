import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_color_picker_sheet.dart';

class ComposerBbCodeContextMenu {
  const ComposerBbCodeContextMenu._();

  static const _insertionService = ComposerBbCodeInsertionService();

  static Widget build(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final buttonItems = <ContextMenuButtonItem>[
      ..._defaultButtonItemsWithoutShare(editableTextState),
      if (_hasSelectedText(editableTextState)) ...[
        ContextMenuButtonItem(
          label: '加粗',
          onPressed: () {
            _applyCommand(editableTextState, composerBoldBbCodeCommand);
          },
        ),
        ContextMenuButtonItem(
          label: '颜色',
          onPressed: () {
            _applyPickedColor(
              context: context,
              editableTextState: editableTextState,
              keyPrefix: 'composer-selection-color',
              title: '字体色',
              initialColor: const Color(0xffd32f2f),
              commandBuilder: (color) => ComposerBbCodeCommand(
                openingTag: '[color=$color]',
                closingTag: '[/color]',
              ),
            );
          },
        ),
        ContextMenuButtonItem(
          label: '背景',
          onPressed: () {
            _applyPickedColor(
              context: context,
              editableTextState: editableTextState,
              keyPrefix: 'composer-selection-backcolor',
              title: '背景色',
              initialColor: const Color(0xfffff3b0),
              commandBuilder: (color) => ComposerBbCodeCommand(
                openingTag: '[backcolor=$color]',
                closingTag: '[/backcolor]',
              ),
            );
          },
        ),
        for (final menuCommand in composerSelectionMenuTrailingBbCodeCommands)
          ContextMenuButtonItem(
            label: menuCommand.label,
            onPressed: () {
              _applyCommand(editableTextState, menuCommand.command);
            },
          ),
      ],
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  static Iterable<ContextMenuButtonItem> _defaultButtonItemsWithoutShare(
    EditableTextState editableTextState,
  ) {
    return editableTextState.contextMenuButtonItems.where(
      (item) => item.type != ContextMenuButtonType.share,
    );
  }

  static bool _hasSelectedText(EditableTextState editableTextState) {
    final selection = editableTextState.textEditingValue.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  static void _applyCommand(
    EditableTextState editableTextState,
    ComposerBbCodeCommand command,
  ) {
    final nextValue = _insertionService.wrapSelection(
      editableTextState.textEditingValue,
      command,
    );
    editableTextState.hideToolbar(false);
    editableTextState.userUpdateTextEditingValue(
      nextValue,
      SelectionChangedCause.toolbar,
    );
    editableTextState.bringIntoView(nextValue.selection.extent);
  }

  static Future<void> _applyPickedColor({
    required BuildContext context,
    required EditableTextState editableTextState,
    required String keyPrefix,
    required String title,
    required Color initialColor,
    required ComposerBbCodeCommand Function(String color) commandBuilder,
  }) async {
    final sourceValue = editableTextState.textEditingValue;
    final colorPicker = showComposerBbCodeColorPickerSheet(
      context: context,
      keyPrefix: keyPrefix,
      title: title,
      initialColor: initialColor,
    );
    editableTextState.hideToolbar(false);
    final color = await colorPicker;
    if (color == null) {
      return;
    }
    final nextValue = _insertionService.wrapSelection(
      sourceValue,
      commandBuilder(color),
    );
    editableTextState.userUpdateTextEditingValue(
      nextValue,
      SelectionChangedCause.toolbar,
    );
    editableTextState.bringIntoView(nextValue.selection.extent);
  }
}
