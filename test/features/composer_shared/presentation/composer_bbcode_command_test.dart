import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';

void main() {
  const service = ComposerBbCodeInsertionService();
  const command = ComposerBbCodeCommand(
    openingTag: '[size=3]',
    closingTag: '[/size]',
  );

  test('wraps selected text and collapses cursor after closing tag', () {
    final result = service.wrapSelection(
      const TextEditingValue(
        text: '前内容后',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      ),
      command,
    );

    expect(result.text, '前[size=3]内容[/size]后');
    expect(result.selection, const TextSelection.collapsed(offset: 18));
  });

  test('inserts empty tags and places cursor between them', () {
    final result = service.wrapSelection(
      const TextEditingValue(
        text: '前后',
        selection: TextSelection.collapsed(offset: 1),
      ),
      command,
    );

    expect(result.text, '前[size=3][/size]后');
    expect(result.selection.baseOffset, 9);
    expect(result.selection.extentOffset, 9);
  });

  test('falls back to appending when selection is invalid', () {
    final result = service.wrapSelection(
      const TextEditingValue(
        text: '正文',
        selection: TextSelection(baseOffset: -1, extentOffset: -1),
      ),
      command,
    );

    expect(result.text, '正文[size=3][/size]');
    expect(result.selection.baseOffset, 10);
    expect(result.selection.extentOffset, 10);
  });

  test(
    'inserts explicit command body and collapses cursor after closing tag',
    () {
      final result = service.wrapSelection(
        const TextEditingValue(
          text: '前后',
          selection: TextSelection.collapsed(offset: 1),
        ),
        const ComposerBbCodeCommand(
          openingTag: '[url=https://example.com]',
          closingTag: '[/url]',
          body: '链接文字',
        ),
      );

      expect(result.text, '前[url=https://example.com]链接文字[/url]后');
      expect(result.selection, const TextSelection.collapsed(offset: 36));
    },
  );

  test('selection menu keeps quote and removes center align shortcut', () {
    final labels = composerSelectionMenuTrailingBbCodeCommands
        .map((command) => command.label)
        .toList();

    expect(labels, containsAllInOrder(<String>['引用', '字号']));
    expect(labels, isNot(contains('居中')));
  });
}
