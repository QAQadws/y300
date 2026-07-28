import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_color_picker_sheet.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComposerBbCodeContextMenu {
  const ComposerBbCodeContextMenu._();

  static const _insertionService = ComposerBbCodeInsertionService();

  static Widget build(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final l10n = AppLocalizations.of(context);
    final buttonItems = <ContextMenuButtonItem>[
      ..._defaultButtonItemsWithoutShare(editableTextState),
      if (_hasSelectedText(editableTextState)) ...[
        ContextMenuButtonItem(
          label: l10n.composerBold,
          onPressed: () {
            _applyCommand(editableTextState, composerBoldBbCodeCommand);
          },
        ),
        ContextMenuButtonItem(
          label: l10n.composerTextColor,
          onPressed: () {
            _applyPickedColor(
              context: context,
              editableTextState: editableTextState,
              keyPrefix: 'composer-selection-color',
              title: l10n.composerTextColor,
              initialColor: const Color(0xffd32f2f),
              commandBuilder: (color) => ComposerBbCodeCommand(
                openingTag: '[color=$color]',
                closingTag: '[/color]',
              ),
            );
          },
        ),
        ContextMenuButtonItem(
          label: l10n.composerBackgroundColor,
          onPressed: () {
            _applyPickedColor(
              context: context,
              editableTextState: editableTextState,
              keyPrefix: 'composer-selection-backcolor',
              title: l10n.composerBackgroundColor,
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
            label: ComposerTextResolver.bbCodeMenuCommand(
              l10n,
              menuCommand.kind,
            ),
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
