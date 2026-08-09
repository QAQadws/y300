import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_collapse_format_sanitizer.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';

void main() {
  const sanitizer = ComposerQuillCollapseFormatSanitizer();
  const codec = ComposerQuillBbCodeCodec();

  test('clears collapse formats without replacing content or selection', () {
    final collapse = composerQuillCollapseEmbedData(
      id: 'collapse-sanitize',
      title: '标题',
      body: '[b]内部[/b]',
    );
    final document = Document.fromDelta(
      Delta()
        ..insert('前', {Attribute.bold.key: true})
        ..insert('\n')
        ..insert(collapse, {
          Attribute.bold.key: true,
          Attribute.color.key: '#ff0000',
        })
        ..insert('\n', {
          Attribute.blockQuote.key: true,
          Attribute.align.key: 'center',
        })
        ..insert('后', {Attribute.bold.key: true})
        ..insert('\n'),
    );
    const selection = TextSelection(baseOffset: 0, extentOffset: 5);
    final controller = QuillController(
      document: document,
      selection: selection,
    );
    addTearDown(controller.dispose);

    final sanitization = sanitizer.buildSanitization(document);
    expect(sanitization, isNotNull);
    controller.compose(sanitization!, selection, ChangeSource.local);

    final operations = controller.document.toDelta().toList();
    final collapseIndex = operations.indexWhere(
      (operation) => composerQuillCollapseEmbedPayload(operation.data) != null,
    );
    final collapseOperation = operations[collapseIndex];
    final collapseLineBreak = operations[collapseIndex + 1];

    expect(collapseOperation.data, collapse);
    expect(collapseOperation.attributes, isNull);
    expect(collapseLineBreak.data, '\n');
    expect(collapseLineBreak.attributes, isNull);
    expect(operations.first.attributes, containsPair(Attribute.bold.key, true));
    expect(
      operations[collapseIndex + 2].attributes,
      containsPair(Attribute.bold.key, true),
    );
    expect(controller.selection, selection);
    expect(
      codec.encodeDocument(controller.document),
      '[b]前[/b]\n'
      '[collapse=0,标题]\n[b]内部[/b][/collapse]\n'
      '[b]后[/b]',
    );
  });

  test('returns no mutation for an already isolated collapse', () {
    final document = Document.fromDelta(
      Delta()
        ..insert(
          composerQuillCollapseEmbedData(
            id: 'collapse-clean',
            title: '标题',
            body: '内容',
          ),
        )
        ..insert('\n'),
    );

    expect(sanitizer.buildSanitization(document), isNull);
  });
}
