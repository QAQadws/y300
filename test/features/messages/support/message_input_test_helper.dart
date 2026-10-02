import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_input.dart';

/// Exercises the actual text-input connection of the compact Quill input.
Future<void> enterMessageText(WidgetTester tester, String text) async {
  final editor = tester.widget<QuillEditor>(
    find.byKey(const Key('message-input')),
  );
  editor.focusNode.requestFocus();
  await tester.pump();
  // Quill exposes its structural final newline to the platform connection.
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: '$text\n',
    selection: TextSelection.collapsed(offset: text.length),
  ));
  await tester.pump();
}

String messageInputValue(WidgetTester tester) => tester
    .widget<ComposerStickerInput>(find.byType(ComposerStickerInput).first)
    .value;

Finder get messageInputSurface => find.byType(ComposerStickerInput).first;
