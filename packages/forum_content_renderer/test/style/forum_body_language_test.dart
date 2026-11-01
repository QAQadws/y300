import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyReaderStyle reader({ForumBodyStylePolicy? policy}) =>
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontSize: 20, locale: Locale('en', 'GB')),
      fontRevision: 'language-test',
      linkColor: const Color(0xff0000ff),
      policy: policy,
    );

void main() {
  for (final (tag, expected) in [
    ('ja', const Locale('ja')),
    (
      'ZH-hANT-tw',
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
    ),
    (
      'sr-Latn',
      const Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn'),
    ),
    (
      'es-419',
      const Locale.fromSubtags(languageCode: 'es', countryCode: '419'),
    ),
    ('fil-PH', const Locale('fil', 'PH')),
    ('und', const Locale('und')),
    ('', const Locale('und')),
  ]) {
    test('native language-script-region tag $tag reaches resolved text', () {
      final document = const ForumBodyParser().parse(
        html: '<p lang="$tag">漢</p>',
        sourceId: 'lang',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(document, reader());
      expect(styles.byPath['0']!.textStyle.locale, expected);
      expect(styles.byPath['0/0']!.textStyle.locale, expected);
      expect(styles.issues, isEmpty);
      expect(
        (document.nodes.single as ForumBodyElement).attributes['lang'],
        tag,
      );
    });
  }

  for (final tag in [
    'ja_JP',
    ' ja',
    'ja ',
    'ja\n',
    'en-US-u-ca-gregory',
    'sl-rozaj',
    'zh-cmn-Hans',
    'x-private',
    'i-klingon',
    'ja-1234',
    'a',
  ]) {
    test(
      'unrepresentable tag $tag is diagnosed without inheriting English',
      () {
        final document = const ForumBodyParser().parse(
          html: '<p lang="$tag">漢<span>漢</span></p>',
          sourceId: 'lang',
          conversionIdentity: 'none',
        );
        final styles = const ForumBodyStyleResolver().resolve(
          document,
          reader(),
        );
        expect(styles.byPath['0']!.textStyle.locale, const Locale('und'));
        expect(styles.byPath['0/1']!.textStyle.locale, const Locale('und'));
        expect(styles.issues.single.property, 'lang');
        expect(styles.issues.single.value, tag);
        expect(
          (document.nodes.single as ForumBodyElement).attributes['lang'],
          tag,
        );
      },
    );
  }

  test(
    'language inheritance survives roles, empty reset, siblings and bounded traversal',
    () {
      final document = const ForumBodyParser().parse(
        html:
            '<div lang="ja"><h2>漢</h2><p>漢'
            '<ruby lang="zh-Hant">漢<rt lang="ko">漢</rt></ruby>'
            '<span lang="">漢<b>漢</b></span><i>漢</i></p></div>'
            '<p xml:lang="ja">漢</p>',
        sourceId: 'lang',
        conversionIdentity: 'none',
      );
      final options = reader(
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
        }),
      );
      final styles = const ForumBodyStyleResolver().resolve(document, options);
      final cursor = const ForumBodyStyleResolver().open(document, options);
      final streamed = <String, Locale?>{};
      while (cursor.moveNext()) {
        streamed[cursor.currentNode!.path] =
            cursor.currentStyle!.textStyle.locale;
      }
      cursor.close();
      expect(
        streamed,
        styles.byPath.map(
          (path, style) => MapEntry(path, style.textStyle.locale),
        ),
      );
      expect(styles.byPath['0/0']!.textStyle.locale, const Locale('ja'));
      expect(
        styles.byPath['0/1/1']!.textStyle.locale,
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      expect(styles.byPath['0/1/1/1']!.textStyle.locale, const Locale('ko'));
      expect(styles.byPath['0/1/2/1']!.textStyle.locale, const Locale('und'));
      expect(styles.byPath['0/1/3']!.textStyle.locale, const Locale('ja'));
      expect(styles.byPath['1']!.textStyle.locale, const Locale('en', 'GB'));
      expect(styles.issues, isEmpty);
    },
  );

  test('HTML lang takes effect while literal xml:lang remains inert', () {
    final document = const ForumBodyParser().parse(
      html:
          '<p lang="ko" xml:lang="ja">漢<span lang="" xml:lang="zh">漢</span></p>',
      sourceId: 'lang',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(document, reader());
    expect(styles.byPath['0']!.textStyle.locale, const Locale('ko'));
    expect(styles.byPath['0/1']!.textStyle.locale, const Locale('und'));
    expect(styles.issues, isEmpty);
  });
}
