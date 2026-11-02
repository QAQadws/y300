import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _readerColor = Color(0xff123456), _red = Color(0xffff0000);
const _blue = Color(0xff0000ff), _magenta = Color(0xffff00ff);
const _html =
    '<div style="color:red;text-emphasis:open sesame red;text-emphasis-position:under left">'
    '<span id="body" style="color:lime;text-emphasis-color:blue">B</span>'
    '<blockquote id="quote">Q<span id="quoteChild">q</span></blockquote>'
    '<pre id="code">C</pre><h2 id="heading">H</h2>'
    '<ruby id="base"><rb id="rb">基</rb>'
    '<rt id="annotation" style="text-emphasis:inherit">音</rt>'
    '<rtc id="level" style="text-emphasis:inherit"><span id="anonymous">匿</span>'
    '<rt id="explicit" style="text-emphasis:inherit;text-emphasis-color:magenta">注</rt>'
    '</rtc><rt id="default">素</rt></ruby>'
    '<a id="link" href="/synthetic">L</a><span id="after">A</span></div>';

ForumBodyReaderStyle _reader(ForumBodyStyleScope scope) => ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    color: _readerColor,
  ),
  fontRevision: 'emphasis-policy',
  linkColor: _blue,
  policy: ForumBodyStylePolicy({ForumBodyStyleProperty.foreground: scope}),
);
ForumBodyDocument _document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'emphasis-policy',
  conversionIdentity: 'none',
);
Map<String, ForumBodyResolvedStyle> _byId(
  ForumBodyDocument doc,
  ForumBodyStyleResult styles,
) => {
  for (final element in doc.descendants.whereType<ForumBodyElement>())
    if (element.attributes['id'] case final String id)
      id: styles.byPath[element.path]!,
};
ForumBodyEmphasisMarkInput _mark(ForumBodyResolvedStyle style) =>
    ForumBodyEmphasisMarkInput(
      style: style,
      fontRevision: 'emphasis-policy',
      styleRevision: ForumBodyStyleResolver.revision,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scope in ForumBodyStyleScope.values) {
    test(
      'shared foreground policy controls marks at actual role boundaries: $scope',
      () {
        final doc = _document(_html);
        final source = doc.sourceText;
        final styles = const ForumBodyStyleResolver().resolve(
          doc,
          _reader(scope),
        );
        final values = _byId(doc, styles);
        expect(styles.issues, isEmpty);
        for (final id in ['body', 'base', 'rb', 'after', 'link']) {
          final style = values[id]!;
          expect(style.role, ForumBodyTextRole.body);
          expect(
            style.textEmphasis.color,
            scope == ForumBodyStyleScope.asDefault
                ? (id == 'body' ? _blue : _red)
                : null,
          );
          expect(
            _mark(style).textStyle.color,
            scope == ForumBodyStyleScope.asDefault
                ? (id == 'body' ? _blue : _red)
                : id == 'link'
                ? _blue
                : _readerColor,
          );
        }
        for (final id in [
          'quote',
          'quoteChild',
          'code',
          'heading',
          'annotation',
          'level',
          'anonymous',
          'explicit',
        ]) {
          final style = values[id]!;
          expect(style.role, isNot(ForumBodyTextRole.body));
          final expected = id == 'explicit' ? _magenta : _red;
          expect(
            style.textEmphasis.color,
            scope == ForumBodyStyleScope.forceAll ? null : expected,
          );
          expect(
            _mark(style).textStyle.color,
            scope == ForumBodyStyleScope.forceAll ? _readerColor : expected,
          );
        }
        for (final style in values.values.where(
          (value) => value.textEmphasis.isEnabled,
        )) {
          expect(style.textEmphasis.shape, ForumBodyEmphasisShape.sesame);
          expect(style.textEmphasis.fill, ForumBodyEmphasisFill.open);
          expect(style.textEmphasis.side, ForumBodyEmphasisSide.under);
          expect(
            style.textEmphasis.verticalSide,
            ForumBodyEmphasisVerticalSide.left,
          );
        }
        expect(values['default']!.textEmphasis.isEnabled, isFalse);
        expect(values['default']!.textEmphasis.color, isNull);
        expect(doc.sourceText, source);
        final body = doc.descendants.whereType<ForumBodyElement>().singleWhere(
          (e) => e.attributes['id'] == 'body',
        );
        expect(body.style.value('text-emphasis-color'), 'blue');
      },
    );
  }
  test(
    'incremental and full style consumers apply the same policy and restoration',
    () {
      final doc = _document(_html);
      final reader = _reader(ForumBodyStyleScope.forceBody);
      final full = const ForumBodyStyleResolver().resolve(doc, reader);
      final cursor = ForumBodyStyledFlowCursor(document: doc, reader: reader);
      var visited = 0;
      try {
        while (cursor.moveNext()) {
          final event = cursor.current!;
          expect(
            event.style.textEmphasis,
            full.byPath[event.node.path]!.textEmphasis,
          );
          visited++;
        }
      } finally {
        cursor.close();
      }
      expect(visited, greaterThan(full.byPath.length));
    },
  );
  test(
    'explicit inherited colors restore across RT/RTC UA defaults for body scope',
    () {
      for (final keyword in ['inherit', 'unset']) {
        final doc = _document(
          '<div style="text-emphasis:dot red">'
          '<ruby>B<rtc id="level" style="text-emphasis:$keyword">'
          '<rt id="column" style="text-emphasis:$keyword">音</rt></rtc></ruby>'
          '<span id="after" style="text-emphasis-color:$keyword">A</span></div>',
        );
        final values = _byId(
          doc,
          const ForumBodyStyleResolver().resolve(
            doc,
            _reader(ForumBodyStyleScope.forceBody),
          ),
        );
        for (final id in ['level', 'column']) {
          expect(values[id]!.textEmphasis.mark, '•');
          expect(values[id]!.textEmphasis.color, _red);
          expect(_mark(values[id]!).textStyle.color, _red);
        }
        expect(values['after']!.textEmphasis.color, isNull);
        expect(_mark(values['after']!).textStyle.color, _readerColor);
      }
    },
  );
  test(
    'background-only policy leaves explicit mark color and transparent values intact',
    () {
      final doc = _document(
        '<div style="text-emphasis:dot red">'
        '<span id="transparent" style="text-emphasis-color:transparent">A</span>'
        '<span id="color">B</span></div>',
      );
      final reader = ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: _readerColor,
        ),
        fontRevision: 'emphasis-policy',
        linkColor: _blue,
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.background: ForumBodyStyleScope.forceAll,
        }),
      );
      final values = _byId(
        doc,
        const ForumBodyStyleResolver().resolve(doc, reader),
      );
      expect(values['color']!.textEmphasis.color, _red);
      expect(
        _mark(values['transparent']!).textStyle.color,
        const Color(0x00000000),
      );
    },
  );
  test(
    'forced color cannot reveal a hidden marker or lose custom shape and position',
    () {
      final doc = _document(
        '<span id="mark" style="visibility:hidden;'
        'text-emphasis:\'X\' red;text-emphasis-position:under left">A</span>',
      );
      final style = _byId(
        doc,
        const ForumBodyStyleResolver().resolve(
          doc,
          _reader(ForumBodyStyleScope.forceAll),
        ),
      )['mark']!;
      expect(style.textEmphasis.color, isNull);
      expect(style.textEmphasis.mark, 'X');
      expect(style.textEmphasis.side, ForumBodyEmphasisSide.under);
      expect(
        style.textEmphasis.verticalSide,
        ForumBodyEmphasisVerticalSide.left,
      );
      expect(_mark(style).textStyle.color, const Color(0x00000000));
    },
  );
  test(
    'reader reset reacquires original native mark without stale forced color',
    () {
      final doc = _document(
        '<span id="mark" style="text-emphasis:dot red">A</span>',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      try {
        final keys = <Object>[];
        final colors = <Color?>[];
        for (final scope in [
          ForumBodyStyleScope.asDefault,
          ForumBodyStyleScope.forceAll,
          ForumBodyStyleScope.asDefault,
        ]) {
          final style = _byId(
            doc,
            const ForumBodyStyleResolver().resolve(doc, _reader(scope)),
          )['mark']!;
          final input = _mark(style);
          colors.add(input.textStyle.color);
          final lease = cache.acquireEmphasisMark(input: input);
          keys.add(lease.nativeInputIdentity);
          lease.release();
        }
        expect(colors, [_red, _readerColor, _red]);
        expect(keys[0], keys[2]);
        expect(keys[0], isNot(keys[1]));
        expect(cache.layoutBuildCount, 2);
      } finally {
        cache.close();
      }
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );
  test(
    'color clone preserves all computed non-color values and shares no-op',
    () {
      const original = ForumBodyTextEmphasis(
        shape: ForumBodyEmphasisShape.custom,
        fill: ForumBodyEmphasisFill.open,
        customMark: 'X',
        color: _red,
        side: ForumBodyEmphasisSide.under,
        verticalSide: ForumBodyEmphasisVerticalSide.left,
      );
      expect(original.withColor(_red), same(original));
      final changed = original.withColor(null);
      expect(changed.withColor(null), same(changed));
      expect(changed.withColor(_red), original);
      expect(changed.mark, 'X');
      expect(changed.fill, original.fill);
      expect(changed.side, original.side);
      expect(changed.verticalSide, original.verticalSide);
    },
  );
}
