import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyReaderStyle reader(Locale locale) => ForumBodyReaderStyle(
  textStyle: TextStyle(
    fontFamily: 'ForumBodyLanguageTest',
    fontSize: 20,
    height: 1,
    locale: locale,
    color: const Color(0xff000000),
  ),
  fontRevision: 'language-fixture-1',
  linkColor: const Color(0xff0000ff),
  paragraphAfter: 0,
);

ForumBodyDocument document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'native-language',
  conversionIdentity: 'none',
);

ForumBodyParagraphContent paragraph(
  ForumBodyDocument body,
  String path, {
  Locale locale = const Locale('en'),
}) => const ForumBodyParagraphContentBuilder().build(
  document: body,
  styles: const ForumBodyStyleResolver().resolve(body, reader(locale)),
  path: path,
  layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final local = File('test/fixtures/fonts/language.ttf');
    final fixture = local.existsSync()
        ? local
        : File(
            'packages/forum_content_renderer/test/fixtures/fonts/language.ttf',
          );
    final bytes = fixture.readAsBytesSync();
    await (FontLoader(
      'ForumBodyLanguageTest',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  test('real locl glyphs follow each inherited/overridden run language', () {
    final input = paragraph(
      document(
        '<p lang="zh">漢<span lang="ja">漢</span><span lang="ko">漢</span></p>',
      ),
      '0',
    );
    final layout = ForumBodyParagraphLayout.create(content: input, width: 100);
    addTearDown(layout.dispose);
    expect(layout.width, closeTo(45, .001));
    expect(layout.selectionBoxes(0, 1).single.right, closeTo(10, .001));
    expect(layout.selectionBoxes(1, 2).single.left, closeTo(10, .001));
    expect(layout.selectionBoxes(1, 2).single.right, closeTo(25, .001));
    expect(layout.selectionBoxes(2, 3).single.left, closeTo(25, .001));
    expect(layout.selectionBoxes(2, 3).single.right, closeTo(45, .001));
    expect(layout.projection.text, '漢漢漢');
  });

  test(
    'empty language clears Host locale and cannot inherit Japanese locl',
    () {
      final input = paragraph(
        document('<p lang="">漢<b>漢</b></p>'),
        '0',
        locale: const Locale('ja'),
      );
      final layout = ForumBodyParagraphLayout.create(
        content: input,
        width: 100,
      );
      addTearDown(layout.dispose);
      expect(input.style.textStyle.locale, const Locale('und'));
      expect(layout.width, closeTo(20, .001));
    },
  );

  test(
    'band batching keeps native language substitutions within each child',
    () {
      final body = document(
        '<p><span lang="ja">漢<span lang="ko">漢</span></span>'
        '<span lang="ja">漢</span></p>',
      );
      final layout = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(
          contexts: [paragraph(body, '0/0'), paragraph(body, '0/1')],
        ),
      );
      addTearDown(layout.dispose);
      expect(layout.view(0).width, closeTo(35, .001));
      expect(layout.view(1).width, closeTo(15, .001));
      expect(
        layout.view(0).selectionBoxes(1, 2).single.right,
        closeTo(35, .001),
      );
    },
  );

  test(
    'cache keys separate effective native locale and reuse author overrides',
    () {
      final owner = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final body = document('<p>漢</p>');
      final english = owner.acquire(content: paragraph(body, '0'), width: 100);
      final japanese = owner.acquire(
        content: paragraph(body, '0', locale: const Locale('ja')),
        width: 100,
      );
      expect(english.layout.width, closeTo(10, .001));
      expect(japanese.layout.width, closeTo(15, .001));
      expect(owner.layoutBuildCount, 2);
      english.release();
      japanese.release();
      final author = document('<p lang="ko">漢</p>');
      final first = owner.acquire(content: paragraph(author, '0'), width: 100);
      final alias = owner.acquire(
        content: paragraph(author, '0', locale: const Locale('ja')),
        width: 100,
      );
      expect(alias.layout, same(first.layout));
      expect(alias.layout.width, closeTo(20, .001));
      expect(owner.layoutBuildCount, 3);
      first.release();
      alias.release();
    },
  );

  test(
    'actual language glyph widths drive pagination without changing source',
    () {
      final body = document(
        '<p lang="zh">漢<span lang="ja">漢</span><span lang="ko">漢</span></p>',
      );
      final owner = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final session = ForumBodyTextPageSession(
        document: body,
        reader: reader(const Locale('en')),
        cache: owner,
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 10,
          maxFragments: 20,
          maxParagraphs: 10,
          maxTextCodeUnits: 100,
          maxRuns: 20,
          maxIssuedLeases: 10,
        ),
        layoutId: 'language-pages',
        width: 25,
        height: 20,
      );
      addTearDown(session.close);
      for (var step = 0; !session.isComplete; step++) {
        if (step > 100) fail('Language page session did not finish');
        session.advance(maxEvents: 32, maxLines: 8);
      }
      final pages = session.snapshot;
      expect(pages.length, 2);
      expect(pages.first.fragments.single.coverageStartUtf16, 0);
      expect(pages.first.fragments.single.coverageEndUtf16, 2);
      expect(pages.last.fragments.single.coverageStartUtf16, 2);
      expect(pages.last.fragments.single.coverageEndUtf16, 3);
      expect(session.takePendingIssues(), isEmpty);
      expect(owner.activeLeases, 0);
    },
  );
}
