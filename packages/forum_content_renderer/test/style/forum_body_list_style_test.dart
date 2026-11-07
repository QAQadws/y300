import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

({ForumBodyDocument document, ForumBodyStyleResult styles}) _resolve(
  String html, {
  ForumBodyStylePolicy? policy,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'list-style',
    conversionIdentity: 'none',
  );
  return (
    document: document,
    styles: const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Selected', fontSize: 20),
        fontRevision: 'selected-font',
        linkColor: const Color(0xff0000ff),
        policy: policy,
      ),
    ),
  );
}

ForumBodyResolvedStyle _id(
  ({ForumBodyDocument document, ForumBodyStyleResult styles}) result,
  String id,
) =>
    result.styles.byPath[result.document.descendants
        .whereType<ForumBodyElement>()
        .singleWhere((element) => element.attributes['id'] == id)
        .path]!;

void main() {
  test(
    'Discuz UL types and classes produce ordered labels without changing IR',
    () {
      for (final (attributes, label) in [
        ('type="1" class="litype_1"', '27.'),
        ('type="a" class="litype_2"', 'aa.'),
        ('type="A" class="litype_3"', 'AA.'),
        ('type="1"', '27.'),
        ('type="a"', 'aa.'),
        ('type="A"', 'AA.'),
        ('class="litype_1"', '27.'),
        ('class="litype_2"', 'aa.'),
        ('class="litype_3"', 'AA.'),
        ('', '•'),
      ]) {
        final result = _resolve('<ul $attributes><li id="item">正文</li></ul>');
        final item = _id(result, 'item');
        expect(item.listStyle.labelFor(27), label, reason: attributes);
        expect(item.role, ForumBodyTextRole.list);
        expect(item.textStyle.fontFamily, 'Selected');
        expect(result.styles.issues, isEmpty);
        expect(
          result.document.descendants.whereType<ForumBodyText>().single.text,
          '正文',
        );
        expect(result.document.sourceMap.runeLength, 2);
      }
    },
  );

  test(
    'HTML ordered types retain case and ordinary UL resets inherited type',
    () {
      for (final (type, label) in [
        ('1', '27.'),
        ('a', 'aa.'),
        ('A', 'AA.'),
        ('i', 'xxvii.'),
        ('I', 'XXVII.'),
      ]) {
        final result = _resolve(
          '<ol type="$type"><li id="outer">outer'
          '<ul><li id="inner">inner</li></ul></li><li id="second">second</li></ol>',
        );
        expect(_id(result, 'outer').listStyle.labelFor(27), label);
        expect(_id(result, 'second').listStyle.labelFor(27), label);
        expect(_id(result, 'inner').listStyle.labelFor(27), '•');
      }
      final plain = _resolve('<ol><li id="item">text</li></ol>');
      expect(_id(plain, 'item').listStyle.labelFor(12), '12.');
    },
  );

  test('inline CSS wins over site class and cascades through real descendants', () {
    final result = _resolve(
      '<ul type="1" class="litype_3" style="list-style: square inside">'
      '<li id="item"><span id="span">base</span><ruby id="ruby">字<rt id="rt">じ</rt></ruby>'
      '<ul style="list-style: inherit"><li id="inner">nested</li></ul></li></ul>',
    );
    for (final id in ['item', 'span', 'ruby', 'rt', 'inner']) {
      expect(
        _id(result, id).listStyle.type,
        ForumBodyListMarkerType.square,
        reason: id,
      );
      expect(
        _id(result, id).listStyle.position,
        ForumBodyListMarkerPosition.inside,
        reason: id,
      );
    }
    expect(result.styles.issues, isEmpty);
  });

  test(
    'valid shorthand resets both components with per-component importance',
    () {
      for (final (declarations, type, position) in [
        (
          'list-style: square inside; list-style-type: decimal',
          ForumBodyListMarkerType.decimal,
          ForumBodyListMarkerPosition.inside,
        ),
        (
          'list-style-type: square !important; list-style: decimal inside',
          ForumBodyListMarkerType.square,
          ForumBodyListMarkerPosition.inside,
        ),
        (
          'list-style: inside !important; list-style-type: square',
          ForumBodyListMarkerType.disc,
          ForumBodyListMarkerPosition.inside,
        ),
        (
          'list-style-position: inside !important; list-style: lower-alpha',
          ForumBodyListMarkerType.lowerAlpha,
          ForumBodyListMarkerPosition.inside,
        ),
        (
          'list-style: inside; list-style: upper-alpha outside !important; list-style-position: inside',
          ForumBodyListMarkerType.upperAlpha,
          ForumBodyListMarkerPosition.outside,
        ),
        (
          'list-style: square inside; list-style: outside',
          ForumBodyListMarkerType.disc,
          ForumBodyListMarkerPosition.outside,
        ),
        (
          'list-style: square inside; list-style: none',
          ForumBodyListMarkerType.none,
          ForumBodyListMarkerPosition.outside,
        ),
        (
          'list-style: none circle inside',
          ForumBodyListMarkerType.circle,
          ForumBodyListMarkerPosition.inside,
        ),
        (
          'list-style: none none inside',
          ForumBodyListMarkerType.none,
          ForumBodyListMarkerPosition.inside,
        ),
      ]) {
        final result = _resolve(
          '<ol id="list" style="$declarations"><li>text</li></ol>',
        );
        expect(
          _id(result, 'list').listStyle,
          ForumBodyListStyle(type: type, position: position),
          reason: declarations,
        );
        expect(result.styles.issues, isEmpty, reason: declarations);
      }
    },
  );

  test(
    'invalid declarations do not shadow valid earlier or later declarations',
    () {
      for (final invalid in [
        'square disc',
        'inside outside',
        'none none none',
        'none none square',
        'url(marker.png) square',
        'custom-counter',
        'initial square',
      ]) {
        final result = _resolve(
          '<ol id="list" style="list-style: circle inside; list-style: $invalid !important; list-style-type: upper-alpha"><li>text</li></ol>',
        );
        final style = _id(result, 'list').listStyle;
        expect(style.type, ForumBodyListMarkerType.upperAlpha, reason: invalid);
        expect(
          style.position,
          ForumBodyListMarkerPosition.inside,
          reason: invalid,
        );
        expect(
          result.styles.issues.single.property,
          'list-style',
          reason: invalid,
        );
      }
      final badLonghands = _resolve(
        '<ul id="list" style="list-style: square inside;list-style-type: invented;list-style-position: nowhere"><li>text</li></ul>',
      );
      expect(
        _id(badLonghands, 'list').listStyle,
        const ForumBodyListStyle(
          type: ForumBodyListMarkerType.square,
          position: ForumBodyListMarkerPosition.inside,
        ),
      );
      expect(badLonghands.styles.issues, hasLength(2));
    },
  );

  test(
    'global keywords and Latin aliases use inherited values and CSS initials',
    () {
      for (final (declaration, expected) in [
        (
          'list-style: unset',
          const ForumBodyListStyle(
            type: ForumBodyListMarkerType.square,
            position: ForumBodyListMarkerPosition.inside,
          ),
        ),
        (
          'list-style: inherit',
          const ForumBodyListStyle(
            type: ForumBodyListMarkerType.square,
            position: ForumBodyListMarkerPosition.inside,
          ),
        ),
        ('list-style: initial', const ForumBodyListStyle()),
        (
          'list-style-type: initial',
          const ForumBodyListStyle(
            position: ForumBodyListMarkerPosition.inside,
          ),
        ),
        (
          'list-style-position: initial',
          const ForumBodyListStyle(type: ForumBodyListMarkerType.decimal),
        ),
        (
          'list-style-type: LOWER-LATIN',
          const ForumBodyListStyle(
            type: ForumBodyListMarkerType.lowerAlpha,
            position: ForumBodyListMarkerPosition.inside,
          ),
        ),
        (
          'list-style-type: upper-latin',
          const ForumBodyListStyle(
            type: ForumBodyListMarkerType.upperAlpha,
            position: ForumBodyListMarkerPosition.inside,
          ),
        ),
      ]) {
        final result = _resolve(
          '<div style="list-style: square inside"><ol id="list" style="$declaration"><li>text</li></ol></div>',
        );
        expect(_id(result, 'list').listStyle, expected, reason: declaration);
        expect(result.styles.issues, isEmpty);
      }
    },
  );

  test('style restoration and derived styles preserve list presentation', () {
    final result = _resolve(
      '<div style="font-size:35px;list-style: upper-alpha inside"><ol style="list-style:inherit"><li id="item" style="text-emphasis:dot">text</li></ol></div>',
      policy: ForumBodyStylePolicy({
        ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
      }),
    );
    final item = _id(result, 'item');
    expect(item.textStyle.fontSize, 35);
    expect(
      item.listStyle,
      const ForumBodyListStyle(
        type: ForumBodyListMarkerType.upperAlpha,
        position: ForumBodyListMarkerPosition.inside,
      ),
    );
    expect(
      item.withTextStyle(item.textStyle.copyWith(fontSize: 24)).listStyle,
      item.listStyle,
    );
  });

  test(
    'number labels cover alphabetic carry, roman bounds and decimal fallback',
    () {
      for (final (type, cases) in [
        (
          ForumBodyListMarkerType.lowerAlpha,
          {
            -1: '-1.',
            0: '0.',
            1: 'a.',
            26: 'z.',
            27: 'aa.',
            52: 'az.',
            53: 'ba.',
            702: 'zz.',
            703: 'aaa.',
          },
        ),
        (
          ForumBodyListMarkerType.upperAlpha,
          {1: 'A.', 26: 'Z.', 27: 'AA.', 703: 'AAA.'},
        ),
        (
          ForumBodyListMarkerType.lowerRoman,
          {
            -1: '-1.',
            0: '0.',
            1: 'i.',
            4: 'iv.',
            9: 'ix.',
            49: 'xlix.',
            99: 'xcix.',
            2026: 'mmxxvi.',
            3999: 'mmmcmxcix.',
            4000: '4000.',
          },
        ),
        (
          ForumBodyListMarkerType.upperRoman,
          {4: 'IV.', 99: 'XCIX.', 3999: 'MMMCMXCIX.', 4000: '4000.'},
        ),
        (
          ForumBodyListMarkerType.decimal,
          {-27: '-27.', 0: '0.', 1: '1.', 27: '27.'},
        ),
      ]) {
        for (final entry in cases.entries) {
          expect(
            ForumBodyListStyle(type: type).labelFor(entry.key),
            entry.value,
            reason: '$type/${entry.key}',
          );
        }
      }
      expect(
        const ForumBodyListStyle(
          type: ForumBodyListMarkerType.none,
        ).labelFor(1),
        isNull,
      );
      expect(
        const ForumBodyListStyle(
          type: ForumBodyListMarkerType.circle,
        ).labelFor(2),
        '◦',
      );
      expect(
        const ForumBodyListStyle(
          type: ForumBodyListMarkerType.square,
        ).labelFor(3),
        '▪',
      );
    },
  );
}
