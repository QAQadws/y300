import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_sticker_text_controller.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_sticker_text_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'prepared comment stickers preserve quoted source and trailing lines',
    () {
      const source = '[quote][b]原文[/b] [em:30:][/quote]\r\n尾行\n';
      final changes = <String>[];
      final controller = ComposerStickerTextController(
        value: source,
        onChanged: changes.add,
        stickers: const [_commentSticker],
      );
      addTearDown(controller.dispose);
      expect(
        const ComposerStickerTextCodec().encodeDocument(
          controller.quill.document,
        ),
        source,
      );
      expect(
        controller.quill.document.toDelta().toList().where(
          (operation) => operation.data is! String,
        ),
        hasLength(1),
      );
      controller.quill.updateSelection(
        TextSelection.collapsed(offset: controller.quill.document.length - 1),
        ChangeSource.local,
      );
      expect(controller.insertSticker(_commentSticker), isTrue);
      expect(controller.source, '$source${_commentSticker.code}');
      expect(changes, ['$source${_commentSticker.code}']);
    },
  );

  test(
    'parent echoes preserve editing while external replacement clears undo',
    () {
      final changes = <String>[];
      final controller = ComposerStickerTextController(
        value: '',
        onChanged: changes.add,
      );
      addTearDown(controller.dispose);
      controller.quill.replaceText(
        0,
        0,
        'sent',
        const TextSelection.collapsed(offset: 4),
      );
      final editedDocument = controller.quill.document;
      final generation = controller.generation;
      controller.update(
        value: 'sent',
        readOnly: false,
        stickers: const [_commentSticker],
      );
      expect(identical(controller.quill.document, editedDocument), isTrue);
      expect(controller.generation, generation);
      expect(controller.quill.hasUndo, isTrue);
      expect(changes, ['sent']);
      controller.loadExternalValue('');
      expect(identical(controller.quill.document, editedDocument), isFalse);
      expect(controller.quill.hasUndo, isFalse);
      expect(controller.quill.hasRedo, isFalse);
      controller.quill.undo();
      controller.quill.redo();
      expect(controller.source, '');
      expect(changes, ['sent']);
    },
  );

  test(
    'read-only and moved selections reject abandoned sticker insertions',
    () {
      final controller = ComposerStickerTextController(
        value: '前后',
        onChanged: (_) {},
      );
      addTearDown(controller.dispose);
      final generation = controller.generation;
      final initialSelection = controller.selection;
      controller.quill.updateSelection(
        const TextSelection.collapsed(offset: 1),
        ChangeSource.local,
      );
      expect(
        controller.canApplyInsertion(generation, initialSelection),
        isFalse,
      );
      final selected = controller.selection;
      controller.update(value: controller.source, readOnly: true);
      expect(controller.canApplyInsertion(generation, selected), isFalse);
      expect(controller.insertSticker(_commentSticker), isFalse);
      expect(controller.source, '前后');
      // A pending/unknown surface remains selectable while mutation is blocked.
      controller.quill.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
        ChangeSource.local,
      );
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      controller.update(value: controller.source, readOnly: false);
      expect(controller.canApplyInsertion(generation, selected), isFalse);
      expect(
        controller.canApplyInsertion(
          controller.generation,
          controller.selection,
        ),
        isTrue,
      );
      expect(controller.insertSticker(_commentSticker), isTrue);
      expect(controller.source, _commentSticker.code);
    },
  );
}

const _commentSticker = StickerItem(
  code: '[em:30:]',
  rawCodePattern: '[em:30:]',
  imagePath: 'comcom/30.gif',
  imageUrl: 'https://bbs.yamibo.com/static/image/smiley/comcom/30.gif',
  cacheKey: 'comment-smiley-30',
);
