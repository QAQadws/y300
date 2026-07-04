import 'package:flutter/services.dart';

class ComposerBbCodeCommand {
  const ComposerBbCodeCommand({
    required this.openingTag,
    required this.closingTag,
    this.body,
  });

  final String openingTag;
  final String closingTag;
  final String? body;
}

class ComposerBbCodeMenuCommand {
  const ComposerBbCodeMenuCommand({required this.label, required this.command});

  final String label;
  final ComposerBbCodeCommand command;
}

const composerBoldBbCodeCommand = ComposerBbCodeCommand(
  openingTag: '[b]',
  closingTag: '[/b]',
);

const composerColorBbCodeCommand = ComposerBbCodeCommand(
  openingTag: '[color=#ff0000]',
  closingTag: '[/color]',
);

const composerBackColorBbCodeCommand = ComposerBbCodeCommand(
  openingTag: '[backcolor=#fff3b0]',
  closingTag: '[/backcolor]',
);

const composerSizeBbCodeCommand = ComposerBbCodeCommand(
  openingTag: '[size=3]',
  closingTag: '[/size]',
);

const composerQuoteBbCodeCommand = ComposerBbCodeCommand(
  openingTag: '[quote]',
  closingTag: '[/quote]',
);

const composerCenterAlignBbCodeCommand = ComposerBbCodeCommand(
  openingTag: '[align=center]',
  closingTag: '[/align]',
);

const composerSelectionMenuTrailingBbCodeCommands = <ComposerBbCodeMenuCommand>[
  ComposerBbCodeMenuCommand(label: '引用', command: composerQuoteBbCodeCommand),
  ComposerBbCodeMenuCommand(label: '字号', command: composerSizeBbCodeCommand),
];

class ComposerBbCodeInsertionService {
  const ComposerBbCodeInsertionService();

  TextEditingValue wrapSelection(
    TextEditingValue value,
    ComposerBbCodeCommand command,
  ) {
    final text = value.text;
    final range = _normalizedSelectionRange(value.selection, text.length);
    final selectedText = text.substring(range.start, range.end);
    final insertedBody = selectedText.isEmpty
        ? command.body ?? ''
        : selectedText;
    final insertedText =
        '${command.openingTag}$insertedBody${command.closingTag}';
    final nextText = text.replaceRange(range.start, range.end, insertedText);
    final bodyStart = range.start + command.openingTag.length;

    return TextEditingValue(
      text: nextText,
      selection: selectedText.isEmpty && insertedBody.isEmpty
          ? TextSelection.collapsed(offset: bodyStart)
          : TextSelection.collapsed(offset: range.start + insertedText.length),
    );
  }
}

({int start, int end}) _normalizedSelectionRange(
  TextSelection selection,
  int textLength,
) {
  if (!selection.isValid) {
    return (start: textLength, end: textLength);
  }
  final start = selection.start.clamp(0, textLength).toInt();
  final end = selection.end.clamp(0, textLength).toInt();
  return start <= end ? (start: start, end: end) : (start: end, end: start);
}
