import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 10, height: 1, fontFamily: 'Ahem'),
  fontRevision: 'ahem',
  linkColor: const Color(0xff0000ff),
);

({ForumBodyDocument document, ForumBodyStyleResult styles}) _resolve(
  String html,
) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'block-box',
    conversionIdentity: 'none',
  );
  return (
    document: document,
    styles: const ForumBodyStyleResolver().resolve(document, _reader),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'nested percentage padding uses each actual containing content width',
    () {
      final result = _resolve(
        '<div style="margin:0 10px;padding:10%">'
        '<p style="margin:0 5%;padding:2px 10%">abcdefghijklmnop</p></div>',
      );
      final outer = ForumBodyBlockBox.resolve(
        style: result.styles.byPath['0']!,
        containingWidth: 200,
        rootFontSize: 10,
        containingDirection: TextDirection.ltr,
      );
      expect(outer.contentLeft, 30);
      expect(outer.contentWidth, 140);
      expect(outer.padding, const EdgeInsets.all(20));
      final inner = ForumBodyBlockBox.resolve(
        style: result.styles.byPath['0/0']!,
        containingWidth: outer.contentWidth,
        rootFontSize: 10,
        containingDirection: TextDirection.ltr,
      );
      expect(inner.contentLeft, 21);
      expect(inner.contentWidth, 98);
      final content = const ForumBodyParagraphContentBuilder().build(
        document: result.document,
        styles: result.styles,
        path: '0/0',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final narrow = cache.acquire(content: content, width: inner.contentWidth);
      final wide = cache.acquire(content: content, width: outer.contentWidth);
      expect(narrow.layout.lines, hasLength(2));
      expect(wide.layout.lines, hasLength(2));
      expect(narrow.layout.lines.first.coverageEndUtf16, 9);
      expect(wide.layout.lines.first.coverageEndUtf16, 14);
      expect(cache.layoutBuildCount, 2);
      narrow.release();
      wide.release();
      expect(cache.activeLeases, 0);
    },
  );

  for (final (css, expectedWidth, expectedLeft, expectedRight) in [
    ('width:80px;margin:0 auto;padding:10px', 80.0, 50.0, 50.0),
    (
      'width:80px;margin-left:auto;margin-right:10px;padding:10px',
      80.0,
      90.0,
      10.0,
    ),
    ('max-width:50%;margin:0 auto;padding:10px', 100.0, 40.0, 40.0),
    (
      'width:180px;max-width:80px;min-width:100px;margin:0 auto',
      100.0,
      50.0,
      50.0,
    ),
    (
      'width:100px;box-sizing:border-box;padding:10px;margin:0 auto',
      80.0,
      50.0,
      50.0,
    ),
    (
      'width:5px;box-sizing:border-box;padding:10px;margin:0 auto',
      0.0,
      90.0,
      90.0,
    ),
    ('margin:0 auto;padding:10px', 180.0, 0.0, 0.0),
  ]) {
    test('normal block equation resolves $css', () {
      final result = _resolve('<div style="$css">x</div>');
      final box = ForumBodyBlockBox.resolve(
        style: result.styles.byPath['0']!,
        containingWidth: 200,
        rootFontSize: 10,
        containingDirection: TextDirection.ltr,
      );
      expect(result.styles.issues, isEmpty);
      expect(box.contentWidth, expectedWidth);
      expect(box.margin.left, expectedLeft);
      expect(box.margin.right, expectedRight);
      expect(box.hasHorizontalOverflow, isFalse);
    });
  }

  for (final direction in ['ltr', 'rtl']) {
    test('over-constrained $direction keeps width and exposes overflow', () {
      final result = _resolve(
        '<div style="width:240px;margin:0 auto;padding:10px">x</div>',
      );
      final box = ForumBodyBlockBox.resolve(
        style: result.styles.byPath['0']!,
        containingWidth: 200,
        rootFontSize: 10,
        containingDirection: direction == 'ltr'
            ? TextDirection.ltr
            : TextDirection.rtl,
      );
      expect(box.contentWidth, 240);
      expect(box.hasHorizontalOverflow, isTrue);
      expect(box.margin.left, direction == 'ltr' ? 0 : -60);
      expect(box.margin.right, direction == 'ltr' ? -60 : 0);
    });
  }

  test('non-auto under-constrained margin follows the block direction', () {
    for (final direction in ['ltr', 'rtl']) {
      final result = _resolve('<div style="width:80px;margin:10px">x</div>');
      final box = ForumBodyBlockBox.resolve(
        style: result.styles.byPath['0']!,
        containingWidth: 200,
        rootFontSize: 10,
        containingDirection: direction == 'ltr'
            ? TextDirection.ltr
            : TextDirection.rtl,
      );
      expect(box.margin.left, direction == 'ltr' ? 10 : 110);
      expect(box.margin.right, direction == 'ltr' ? 110 : 10);
      expect(box.contentLeft, direction == 'ltr' ? 10 : 110);
      expect(box.margin.top, 10);
    }
  });

  test(
    'child text direction does not change the containing direction equation',
    () {
      final result = _resolve(
        '<div dir="rtl" style="width:80px;margin:10px">אבג</div>',
      );
      final box = ForumBodyBlockBox.resolve(
        style: result.styles.byPath['0']!,
        containingWidth: 200,
        containingDirection: TextDirection.ltr,
        rootFontSize: 10,
      );
      expect(box.contentLeft, 10);
      expect(result.styles.byPath['0']!.textDirection, TextDirection.rtl);
    },
  );

  test(
    'vertical auto is zero while signed percentage margins retain their value',
    () {
      final result = _resolve(
        '<div style="margin:auto 0 -5%;padding:10%">x</div>',
      );
      final box = ForumBodyBlockBox.resolve(
        style: result.styles.byPath['0']!,
        containingWidth: 200,
        rootFontSize: 10,
        containingDirection: TextDirection.ltr,
      );
      expect(box.margin.top, 0);
      expect(box.margin.bottom, -10);
      expect(box.padding.top, 20);
      expect(box.padding.bottom, 20);
    },
  );

  test(
    'unsupported display and non-finite inputs never become native geometry',
    () {
      final result = _resolve('<span>x</span><div>x</div>');
      expect(
        () => ForumBodyBlockBox.resolve(
          style: result.styles.byPath['0']!,
          containingWidth: 100,
          rootFontSize: 10,
          containingDirection: TextDirection.ltr,
        ),
        throwsA(
          isA<ForumBodyBlockBoxException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyBlockBoxFailure.display,
          ),
        ),
      );
      for (final width in [-1.0, double.nan, double.infinity]) {
        expect(
          () => ForumBodyBlockBox.resolve(
            style: result.styles.byPath['1']!,
            containingWidth: width,
            rootFontSize: 10,
            containingDirection: TextDirection.ltr,
          ),
          throwsA(isA<ForumBodyBlockBoxException>()),
        );
      }
    },
  );
}
