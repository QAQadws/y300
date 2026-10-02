import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_sticker_text_codec.dart';

void main() {
  const codec = ComposerStickerTextCodec();

  test('preserves text, Unicode, BBCode and every user newline', () {
    for (final source in [
      '',
      '\n',
      '文字😀',
      'tail\n',
      'tail\n\n',
      '\n\n',
      'a\r\nb',
      '[b]bold[/b] [attach]123[/attach] [collapse=0]body[/collapse]',
    ]) {
      final document = codec.decodeDocument(source);
      expect(codec.encodeDocument(document), source);
      expect(
        document.toDelta().toList().every((op) => op.data is String),
        isTrue,
      );
    }
  });

  test('known codes become atomic stickers using longest literal match', () {
    const source = '甲:))乙:) {:9_656:}\n';
    final document = codec.decodeDocument(
      source,
      stickerCodes: [':)', ':))', '{:9_656:}'],
    );
    final embeds = document.toDelta().toList().where(
      (op) => op.data is! String,
    );
    expect(embeds.map((op) => op.data), [
      {'sticker': ':))'},
      {'sticker': ':)'},
      {'sticker': '{:9_656:}'},
    ]);
    expect(codec.encodeDocument(document), source);
  });

  test('unknown codes remain editable text without a catalog', () {
    final document = codec.decodeDocument('unknown {:9_656:}');
    expect(document.toPlainText(), 'unknown {:9_656:}\n');
  });

  test('fragment has no document sentinel or formatting attributes', () {
    final fragment = codec.decodeFragment(
      'a\n{:9_656:}',
      stickerCodes: ['{:9_656:}'],
    );
    expect(
      fragment.toList().fold<int>(0, (length, op) => length + op.length!),
      3,
    );
    expect(fragment.last.data, {'sticker': '{:9_656:}'});
    expect(fragment.toList().every((op) => op.attributes == null), isTrue);
  });

  test('incidental Quill styles never generate BBCode', () {
    final document = Document.fromDelta(
      Delta()
        ..insert('plain', {'bold': true, 'link': 'https://example.com'})
        ..insert('\n', {'header': 1}),
    );
    expect(codec.encodeDocument(document), 'plain');
  });

  test('an unsupported embed is not silently dropped', () {
    final document = Document.fromDelta(
      Delta()
        ..insert({'image': 'https://example.com/a.png'})
        ..insert('\n'),
    );
    expect(() => codec.encodeDocument(document), throwsStateError);
  });
}
