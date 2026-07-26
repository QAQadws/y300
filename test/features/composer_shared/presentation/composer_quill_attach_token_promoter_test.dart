import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_attach_token_promoter.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';

void main() {
  const promoter = ComposerQuillAttachTokenPromoter();
  const codec = ComposerQuillBbCodeCodec();

  Document documentWithText(String text, {Map<String, dynamic>? attributes}) {
    final delta = Delta();
    if (text.isNotEmpty) {
      delta.insert(text, attributes);
    }
    delta.insert('\n');
    return Document.fromDelta(delta);
  }

  List<Object?> insertedData(Document document) {
    return document
        .toDelta()
        .toList()
        .where((operation) => operation.isInsert)
        .map((operation) => operation.data)
        .toList(growable: false);
  }

  Document applyPromotion(Document document) {
    final promotion = promoter.buildPromotion(document);
    expect(promotion, isNotNull);
    document.compose(promotion!, ChangeSource.local);
    return document;
  }

  test('promotes a literal attach token into an embed', () {
    final document = documentWithText('[attach]1626084[/attach]');

    final promoted = applyPromotion(document);

    expect(insertedData(promoted), [
      composerQuillAttachEmbedData('1626084'),
      '\n',
    ]);
  });

  test('keeps the surrounding text intact', () {
    final document = documentWithText('前[attach]12[/attach]后');

    final promoted = applyPromotion(document);

    expect(insertedData(promoted), [
      '前',
      composerQuillAttachEmbedData('12'),
      '后\n',
    ]);
  });

  test('promotes every token in one delta', () {
    final document = documentWithText(
      '[attach]1[/attach]和[attach]22[/attach]',
    );

    final promoted = applyPromotion(document);

    expect(insertedData(promoted), [
      composerQuillAttachEmbedData('1'),
      '和',
      composerQuillAttachEmbedData('22'),
      '\n',
    ]);
  });

  test('inherits the inline style at the token start', () {
    final document = documentWithText(
      '[attach]12[/attach]',
      attributes: <String, dynamic>{Attribute.bold.key: true},
    );

    final promoted = applyPromotion(document);

    final embedOperation = promoted
        .toDelta()
        .toList()
        .firstWhere((operation) => operation.data is Map);
    expect(embedOperation.attributes, <String, dynamic>{
      Attribute.bold.key: true,
    });
    expect(codec.encodeDocument(promoted), '[b][attach]12[/attach][/b]');
  });

  test('returns null when the document has no literal token', () {
    expect(promoter.buildPromotion(documentWithText('普通文本')), isNull);
    expect(promoter.buildPromotion(Document()), isNull);
  });

  test('returns null for an already promoted document', () {
    final document = codec.decodeDocument('[attach]1626084[/attach]');

    expect(promoter.buildPromotion(document), isNull);
  });

  test('leaves illegal tokens as editable text', () {
    expect(
      promoter.buildPromotion(documentWithText('[attach]abc[/attach]')),
      isNull,
    );
    expect(
      promoter.buildPromotion(documentWithText('[attach][/attach]')),
      isNull,
    );
  });

  test('offsets stay correct next to an existing embed', () {
    final document = codec.decodeDocument('{:9_656:}');
    document.insert(1, '[attach]12[/attach]');

    final promoted = applyPromotion(document);

    expect(insertedData(promoted), [
      composerQuillStickerEmbedData('{:9_656:}'),
      composerQuillAttachEmbedData('12'),
      '\n',
    ]);
  });

  test('promotion is BBCode neutral', () {
    final document = documentWithText('前[attach]12[/attach]后');
    final before = codec.encodeDocument(document);

    final promoted = applyPromotion(document);

    expect(codec.encodeDocument(promoted), before);
  });
}
