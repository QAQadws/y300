import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_message_insertion_service.dart';

void main() {
  const service = ComposerMessageInsertionService();

  test(
    'inserts one attachment into an empty source and moves to next line',
    () {
      final mutation = service.insertAttachmentBlock(
        source: '',
        selection: const ComposerSelection(start: 0, end: 0),
        attachmentCodes: const ['[attach]1[/attach]'],
        revision: 1,
      );

      expect(mutation.nextSource, '[attach]1[/attach]\n');
      expect(
        mutation.resultSelection,
        const ComposerSelection(start: 19, end: 19),
      );
    },
  );

  test('inserts a block in the middle and replaces a selection', () {
    final mutation = service.insertAttachmentBlock(
      source: '你好世界',
      selection: const ComposerSelection(start: 2, end: 4),
      attachmentCodes: const ['[attach]123[/attach]'],
      revision: 3,
    );

    expect(mutation.nextSource, '你好\n[attach]123[/attach]\n');
    expect(
      mutation.replacedSelection,
      const ComposerSelection(start: 2, end: 4),
    );
    expect(
      mutation.resultSelection,
      const ComposerSelection(start: 24, end: 24),
    );
  });

  test(
    'preserves existing line breaks and inserts multiple codes in order',
    () {
      final source = '前\n\n后';
      final mutation = service.insertAttachmentBlock(
        source: source,
        selection: const ComposerSelection(start: 3, end: 3),
        attachmentCodes: const ['[attach]1[/attach]', '[attach]2[/attach]'],
        revision: 1,
      );

      expect(
        mutation.nextSource,
        '前\n\n[attach]1[/attach]\n[attach]2[/attach]\n后',
      );
    },
  );

  test('uses UTF-16 offsets for emoji without corrupting source', () {
    const source = 'A😀B';
    final mutation = service.insertAttachmentBlock(
      source: source,
      selection: const ComposerSelection(start: 3, end: 3),
      attachmentCodes: const ['[attach]9[/attach]'],
      revision: 1,
    );

    expect(mutation.nextSource, 'A😀\n[attach]9[/attach]\nB');
  });
}
