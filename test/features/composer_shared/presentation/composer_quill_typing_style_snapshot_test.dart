import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_typing_style_snapshot.dart';

void main() {
  test(
    'typing style snapshot replaces nearby inline styles at document end',
    () {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      controller.replaceText(
        0,
        0,
        '普通末尾',
        const TextSelection.collapsed(offset: 4),
      );
      controller.formatText(2, 2, Attribute.italic);
      controller.formatText(2, 2, Attribute.clone(Attribute.color, '#d32f2f'));
      controller.formatText(
        2,
        2,
        Attribute.clone(Attribute.link, 'https://example.com'),
      );
      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      controller.formatSelection(Attribute.bold);

      final snapshot = ComposerQuillTypingStyleSnapshot.capture(controller);
      controller.updateSelection(
        const TextSelection.collapsed(offset: 4),
        ChangeSource.local,
      );
      snapshot.restore(controller);
      controller.replaceText(
        4,
        0,
        '新',
        const TextSelection.collapsed(offset: 5),
      );

      final insertedStyle = controller.document.collectStyle(4, 1).attributes;
      expect(insertedStyle[Attribute.bold.key]?.value, isTrue);
      expect(insertedStyle[Attribute.italic.key], isNull);
      expect(insertedStyle[Attribute.color.key], isNull);
      expect(insertedStyle[Attribute.link.key], isNull);
    },
  );
}
