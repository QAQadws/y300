import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyReaderStyle reader({
  ForumBodyStylePolicy? policy,
  ForumBodyLength indent = ForumBodyLength.zero,
}) => ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'ReaderFont',
    fontSize: 20,
    height: 1.6,
    color: Color(0xff202020),
    fontWeight: FontWeight.w500,
    letterSpacing: 1.5,
    wordSpacing: 2,
  ),
  fontRevision: 'test-font-v1',
  linkColor: const Color(0xff0044cc),
  firstLineIndent: indent,
  policy: policy,
  textAlign: TextAlign.justify,
);

({ForumBodyDocument document, ForumBodyStyleResult styles}) resolve(
  String html, {
  ForumBodyReaderStyle? options,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'styles',
    conversionIdentity: 'none',
  );
  return (
    document: document,
    styles: const ForumBodyStyleResolver().resolve(
      document,
      options ?? reader(),
    ),
  );
}

ForumBodyResolvedStyle byId(
  ({ForumBodyDocument document, ForumBodyStyleResult styles}) result,
  String id,
) {
  final element = result.document.descendants
      .whereType<ForumBodyElement>()
      .firstWhere((node) => node.attributes['id'] == id);
  return result.styles.byPath[element.path]!;
}

void main() {
  test('body-only overrides restore author inheritance at semantic roles', () {
    final result = resolve(
      '<div style="font-size:30px;line-height:24px;'
      'text-align:center;letter-spacing:3px;word-spacing:4px;'
      'font-weight:100;text-indent:2em;color:red">'
      '<p id="p" style="margin:15px 12px">正文</p>'
      '<h2 id="h">标题<span id="s">副标题</span></h2>'
      '<blockquote id="q">引用</blockquote></div>',
      options: reader(
        policy: ForumBodyStylePolicy({
          for (final property in ForumBodyStyleProperty.values)
            property: ForumBodyStyleScope.forceBody,
        }),
      ),
    );
    final body = byId(result, 'p');
    expect(body.textStyle.fontSize, 20);
    expect(body.textStyle.height, 1.6);
    expect(body.textStyle.fontWeight, FontWeight.w500);
    expect(body.textStyle.letterSpacing, 1.5);
    expect(body.textStyle.wordSpacing, 2);
    expect(body.textStyle.color, const Color(0xff202020));
    expect(body.textAlign, TextAlign.justify);
    expect(body.indent.value, 0);
    expect(body.margin.top.value, 0);
    expect(body.margin.bottom.value, 10);
    expect(body.margin.left.value, 12);
    for (final id in ['h', 's', 'q']) {
      final style = byId(result, id);
      expect(style.textAlign, TextAlign.center, reason: id);
      expect(style.textStyle.fontSize, id == 'q' ? 30 : 45, reason: id);
      expect(style.lineHeight.pixels, 24, reason: id);
      expect(style.textStyle.letterSpacing, 3, reason: id);
      expect(style.textStyle.wordSpacing, 4, reason: id);
      expect(style.textStyle.color, const Color(0xffff0000), reason: id);
      expect(style.indent.value, 60, reason: id);
    }
    expect(result.styles.issues, isEmpty);
  });

  test(
    'headings keep author ancestor alignment but exclude reader-only justify',
    () {
      final authored = resolve(
        '<div style="text-align:center;font-size:30px">'
        '<h2 id="h"><span id="s">标题</span></h2></div>',
      );
      expect(byId(authored, 'h').textStyle.fontSize, 45);
      expect(byId(authored, 'h').textAlign, TextAlign.center);
      expect(byId(authored, 's').textAlign, TextAlign.center);
      final implicit = resolve('<h2 id="h"><span id="s">标题</span></h2>');
      expect(byId(implicit, 'h').textAlign, TextAlign.start);
      expect(byId(implicit, 's').textAlign, TextAlign.start);
      final explicit = resolve('<h2 id="h" style="text-align:inherit">标题</h2>');
      expect(byId(explicit, 'h').textAlign, TextAlign.justify);
    },
  );

  test(
    'relative and explicit inherited weights use the parent computed weight',
    () {
      final result = resolve(
        '<p style="font-weight:400">'
        '<strong id="a" style="font-weight:bolder">A</strong>'
        '<strong id="b" style="font-weight:inherit">B</strong></p>'
        '<p style="font-weight:900"><strong id="c">C</strong></p>',
      );
      expect(byId(result, 'a').textStyle.fontWeight, FontWeight.w700);
      expect(byId(result, 'b').textStyle.fontWeight, FontWeight.w400);
      expect(byId(result, 'c').textStyle.fontWeight, FontWeight.w900);
    },
  );

  test(
    'author issue provenance is retained once when a body setting overrides it',
    () {
      final result = resolve(
        '<p style="word-spacing:20%">body</p>',
        options: reader(
          policy: ForumBodyStylePolicy({
            ForumBodyStyleProperty.wordSpacing: ForumBodyStyleScope.forceBody,
          }),
        ),
      );
      expect(
        result.styles.issues.where((issue) => issue.property == 'word-spacing'),
        hasLength(1),
      );
    },
  );

  test(
    'unit parsing keeps percentages/auto deferred and resolves font units',
    () {
      expect(
        ForumBodyLength.tryParse(
          ' 1.5REM ',
        )?.computed(fontSize: 10, rootFontSize: 20),
        const ForumBodyLength(30),
      );
      expect(
        ForumBodyLength.tryParse(
          '12pt',
        )?.resolve(fontSize: 10, rootFontSize: 20, reference: 100),
        16,
      );
      expect(ForumBodyLength.tryParse('1'), isNull);
      expect(ForumBodyLength.tryParse('NaNpx'), isNull);
      expect(ForumBodyLength.tryParse('calc(100% - 2px)'), isNull);
      expect(ForumBodyInsets.tryParse('1px 2px 3px 4px 5px'), isNull);
      final auto = ForumBodyLength.tryParse('auto')!;
      expect(
        () => auto.resolve(fontSize: 20, rootFontSize: 20, reference: 300),
        throwsStateError,
      );
    },
  );

  test(
    'case-insensitive keywords and shorthand importance share one cascade',
    () {
      final result = resolve(
        '<p id="p" style="FONT-SIZE:150%;text-align:CENTER;'
        'font-weight:BOLD;background:RED!important;background-color:blue;'
        'text-decoration:underline!important;text-decoration-line:line-through">x</p>',
      );
      final style = byId(result, 'p');
      expect(style.textStyle.fontSize, 30);
      expect(style.textStyle.fontWeight, FontWeight.bold);
      expect(style.textAlign, TextAlign.center);
      expect(style.boxBackground, const Color(0xffff0000));
      expect(
        style.textStyle.decoration!.contains(TextDecoration.underline),
        isTrue,
      );
      expect(
        style.textStyle.decoration!.contains(TextDecoration.lineThrough),
        isFalse,
      );
      expect(result.styles.issues, isEmpty);
    },
  );

  test('inline descendants cannot erase ancestor decoration or background', () {
    final result = resolve(
      '<u style="background:red"><span id="c" '
      'style="text-decoration:none;background:transparent">x</span></u>'
      '<a id="a" href="x" style="text-decoration:none">link</a>',
    );
    expect(
      byId(
        result,
        'c',
      ).textStyle.decoration!.contains(TextDecoration.underline),
      isTrue,
    );
    expect(
      byId(result, 'c').textStyle.backgroundColor,
      const Color(0xffff0000),
    );
    expect(byId(result, 'a').textStyle.decoration, TextDecoration.none);
  });

  test(
    'box inherit is explicit; negative or auto padding rejects a declaration',
    () {
      final result = resolve(
        '<div style="font-size:10px;margin:2em;padding:3px">'
        '<p id="p" style="font-size:20px;margin:inherit;margin-left:initial;'
        'padding:inherit;padding:1px -2px;padding-top:auto;padding-left:unset">x</p></div>',
      );
      final style = byId(result, 'p');
      expect(style.margin.top.value, 20);
      expect(style.margin.left.value, 0);
      expect(style.padding.top.value, 3);
      expect(style.padding.right.value, 3);
      expect(style.padding.left.value, 0);
      expect(
        result.styles.issues.map((issue) => issue.property),
        containsAll(['padding', 'padding-top']),
      );
    },
  );

  test(
    'system family can leave semantic code and fold summaries stay hidden',
    () {
      final result = resolve(
        '<pre>code<h2 id="h">heading</h2></pre>'
        '<div class="showcollapse_gather" id="g">summary</div>',
        options: ForumBodyReaderStyle(
          textStyle: const TextStyle(fontSize: 20),
          fontRevision: 'system',
          linkColor: const Color(0xff0000ff),
        ),
      );
      expect(byId(result, 'h').textStyle.fontFamily, isNull);
      expect(byId(result, 'g').hidden, isTrue);
    },
  );

  test(
    'author sizes and fixed line heights inherit without multiplying twice',
    () {
      final result = resolve(
        '<p id="p" style="font-size:12px;line-height:28px">'
        '<span id="c" style="font-size:20px">text</span></p>',
      );
      expect(byId(result, 'p').textStyle.height, closeTo(28 / 12, 0.00001));
      expect(byId(result, 'c').textStyle.height, closeTo(28 / 20, 0.00001));
      expect(result.styles.issues, isEmpty);
    },
  );

  test(
    'numeric line height inherits as a factor; percentage is computed first',
    () {
      for (final (height, expected) in [('1.8', 1.8), ('150%', .9)]) {
        final result = resolve(
          '<p style="font-size:12px;line-height:$height">'
          '<span id="c" style="font-size:20px">text</span></p>',
        );
        expect(byId(result, 'c').textStyle.height, closeTo(expected, 0.00001));
      }
      final natural = resolve(
        '<p id="n" style="line-height:normal">natural</p>',
      );
      expect(byId(natural, 'n').textStyle.height, kTextHeightNone);
    },
  );

  test('reader body override wins over fixed author size and line height', () {
    final result = resolve(
      '<p id="p" style="font-size:12px;line-height:16px;'
      'text-align:right">正文</p><h2 id="h" align="center">标题</h2>',
      options: reader(
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
          ForumBodyStyleProperty.lineHeight: ForumBodyStyleScope.forceBody,
          ForumBodyStyleProperty.textAlign: ForumBodyStyleScope.forceBody,
        }),
      ),
    );
    expect(byId(result, 'p').textStyle.fontSize, 20);
    expect(byId(result, 'p').textStyle.height, 1.6);
    expect(byId(result, 'p').textAlign, TextAlign.justify);
    expect(byId(result, 'h').textStyle.fontSize, 30);
    expect(byId(result, 'h').textAlign, TextAlign.center);
  });

  test(
    'selected family survives nested author fonts; code remains semantic',
    () {
      final result = resolve(
        '<font id="a" face="Missing" style="font-family:Other">'
        '<b id="b">bold</b></font><code id="c">code</code>',
      );
      expect(byId(result, 'a').textStyle.fontFamily, 'ReaderFont');
      expect(byId(result, 'b').textStyle.fontFamily, 'ReaderFont');
      expect(byId(result, 'b').textStyle.fontWeight, FontWeight.w700);
      expect(byId(result, 'c').textStyle.fontFamily, 'monospace');
      expect(byId(result, 'c').whiteSpace, ForumBodyWhiteSpace.preWrap);
      expect(byId(result, 'c').display, ForumBodyDisplay.inline);
    },
  );

  test('body-weight override retains emphasis and nested decoration', () {
    final result = resolve(
      '<p id="p" style="font-weight:100">'
      '<strong id="s"><u><strike id="d">text</strike></u></strong></p>',
      options: reader(
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.fontWeight: ForumBodyStyleScope.forceBody,
        }),
      ),
    );
    expect(byId(result, 'p').textStyle.fontWeight, FontWeight.w500);
    expect(byId(result, 's').textStyle.fontWeight, FontWeight.w700);
    final decoration = byId(result, 'd').textStyle.decoration!;
    expect(decoration.contains(TextDecoration.underline), isTrue);
    expect(decoration.contains(TextDecoration.lineThrough), isTrue);
  });

  test('relative sizes use parent/root; Discuz size uses body scale', () {
    final result = resolve(
      '<div style="font-size:30px"><span id="a" '
      'style="font-size:150%">A</span><span id="b" style="font-size:1rem">B</span>'
      '<font id="c" size="5">C</font></div>',
    );
    expect(byId(result, 'a').textStyle.fontSize, 45);
    expect(byId(result, 'b').textStyle.fontSize, 20);
    expect(byId(result, 'c').textStyle.fontSize, 25);
  });

  test('word/letter spacing are separate inputs with explicit overrides', () {
    final authored = resolve(
      '<p id="p" style="letter-spacing:.1em;word-spacing:3pt">X</p>',
    );
    expect(byId(authored, 'p').textStyle.letterSpacing, 2);
    expect(byId(authored, 'p').textStyle.wordSpacing, 4);
    final forced = resolve(
      '<p id="p" style="letter-spacing:8px;word-spacing:9px">X</p>',
      options: reader(
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.letterSpacing: ForumBodyStyleScope.forceBody,
          ForumBodyStyleProperty.wordSpacing: ForumBodyStyleScope.forceBody,
        }),
      ),
    );
    expect(byId(forced, 'p').textStyle.letterSpacing, 1.5);
    expect(byId(forced, 'p').textStyle.wordSpacing, 2);
  });

  test('reader indent does not leak into headings or code', () {
    final result = resolve(
      '<p id="p">正文</p><h2 id="h">标题</h2>'
      '<pre id="c">code</pre>',
      options: reader(indent: const ForumBodyLength(2, ForumBodyLengthUnit.em)),
    );
    expect(byId(result, 'p').indent.value, 2);
    expect(byId(result, 'h').indent, ForumBodyLength.zero);
    expect(byId(result, 'h').textAlign, TextAlign.start);
    expect(byId(result, 'c').indent, ForumBodyLength.zero);
  });

  test('relative author indent computes before child inheritance', () {
    final result = resolve(
      '<div style="font-size:10px;text-indent:2em">'
      '<p id="p" style="font-size:20px">text</p></div>',
    );
    expect(byId(result, 'p').indent, const ForumBodyLength(20));
    final percent = resolve('<p id="p" style="text-indent:10%">text</p>');
    expect(byId(percent, 'p').indent.unit, ForumBodyLengthUnit.percent);
    expect(
      byId(
        percent,
        'p',
      ).indent.resolve(fontSize: 20, rootFontSize: 20, reference: 300),
      30,
    );
  });

  test('box cascade accounts for important shorthand and non-inheritance', () {
    final result = resolve(
      '<div id="a" style="margin:1px 2px 3px 4px!important;'
      'margin-left:99px"><span id="b">text</span></div>',
    );
    final margin = byId(result, 'a').margin;
    expect(
      [
        margin.top.value,
        margin.right.value,
        margin.bottom.value,
        margin.left.value,
      ],
      [1, 2, 3, 4],
    );
    expect(byId(result, 'b').margin.top.value, 0);
  });

  test(
    'hidden template/display cannot leak; visibility may be reset by a child',
    () {
      final result = resolve(
        '<div style="display:none"><span id="d">hidden</span></div>'
        '<div style="visibility:hidden"><span id="v" style="visibility:visible">'
        'visible</span></div><template id="t">not displayed</template>'
        '<div class="showcollapse_content" id="f" style="display:none">fold</div>',
      );
      expect(byId(result, 'd').hidden, isTrue);
      expect(byId(result, 'v').visibilityHidden, isFalse);
      expect(byId(result, 't').hidden, isTrue);
      expect(byId(result, 'f').hidden, isFalse);
    },
  );

  test(
    'paint colors reuse shared interpretation and distinguish block backgrounds',
    () {
      final result = resolve(
        '<p id="p" style="background-color:#ff000080">'
        '<font id="f" color="DarkRed">red</font><span id="i" '
        'style="background-color:rgba(0,255,0,.5)">green</span>'
        '<a id="a" href="forum.php?tid=100">link</a></p>',
      );
      expect(byId(result, 'p').boxBackground, const Color(0x80ff0000));
      expect(byId(result, 'f').textStyle.color, const Color(0xff8b0000));
      expect(
        byId(result, 'i').textStyle.backgroundColor,
        const Color(0x8000ff00),
      );
      expect(byId(result, 'a').textStyle.color, const Color(0xff0044cc));
      expect(byId(result, 'a').linkTarget, 'forum.php?tid=100');
    },
  );

  test(
    'unsupported geometry is reported rather than delegated to another renderer',
    () {
      final result = resolve(
        '<p id="p" style="width:calc(100% - 1px);'
        'font-size:999999px;word-spacing:20%;display:grid">text</p>',
      );
      expect(
        result.styles.issues.map((issue) => issue.property),
        containsAll(['width', 'font-size', 'word-spacing', 'display']),
      );
      expect(byId(result, 'p').textStyle.fontSize, 20);
    },
  );

  test('resolution preserves document/font identity and immutable output', () {
    final result = resolve('<p>body</p>');
    expect(result.styles.identity, result.document.identity);
    expect(result.styles.fontRevision, 'test-font-v1');
    expect(() => result.styles.byPath.clear(), throwsUnsupportedError);
    expect(() => result.styles.issues.clear(), throwsUnsupportedError);
    expect(() => reader().policy.values.clear(), throwsUnsupportedError);
    expect(
      () => ForumBodyReaderStyle(
        textStyle: const TextStyle(fontSize: double.nan),
        fontRevision: 'invalid',
        linkColor: const Color(0xff000000),
      ),
      throwsArgumentError,
    );
  });
}
