import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _limits = ForumBodyTextPageSessionLimits(
  maxPages: 48,
  maxFragments: 128,
  maxParagraphs: 64,
  maxTextCodeUnits: 4096,
  maxRuns: 256,
  maxIssuedLeases: 16,
);

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
  fontRevision: 'table-layout',
  linkColor: const Color(0xff0000ff),
  paragraphAfter: 0,
);

ForumBodyDocument _parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'table-layout',
  conversionIdentity: 'none',
);

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 24,
    maxEstimatedBytes: 1 << 22,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyTablePreparation _start(
  ForumBodyDocument document,
  ForumBodyParagraphCache cache, {
  double availableWidth = 120,
  ForumBodyTextPageSessionLimits limits = _limits,
  ForumBodyImageResolver? images,
}) {
  final work = ForumBodyTablePreparation(
    document: document,
    table: document.tableElements.single,
    reader: _reader,
    cache: cache,
    layoutId: 'table-layout',
    availableWidth: availableWidth,
    limits: limits,
    imageResolver: images,
  );
  addTearDown(work.close);
  return work;
}

ForumBodyTableLayout _layout(ForumBodyTablePreparation work) {
  for (var i = 0; i < 10000 && !work.isReady; i++) {
    final step = work.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
  }
  expect(work.isReady, isTrue);
  final layout = work.takeLayout();
  addTearDown(layout.close);
  return layout;
}

List<ForumBodyPreparedTextFragment> _open(ForumBodyTableAreaLayout cell) {
  final prep = cell.openPagePreparation(0);
  try {
    for (var i = 0; i < 1000 && !prep.isReady; i++) {
      prep.advance(maxFragments: 1, maxParts: 1);
    }
    return prep.takeFragments();
  } finally {
    prep.close();
  }
}

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource();
  @override
  String get cacheKey => 'table-cell-image';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a measured table body paints at its occupied height', (
    tester,
  ) async {
    final document = _parse(
      '<table><tr><td><a href="/thread">link</a></td></tr></table>',
    );
    final cache = _cache();
    final layout = _layout(_start(document, cache));
    final cell = layout.cells.single;
    final snapshot = cell.snapshot;
    final fragments = _open(cell);
    final point = fragments.single.glyphBoxes(0, 1).single.toRect().center;
    final hits = <int>[];
    const key = ValueKey('measured-cell');
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: SizedBox.fromSize(
            size: cell.contentBounds.size,
            child: ForumBodyTextPageSurface.prepared(
              key: key,
              snapshot: snapshot,
              pageIndex: 0,
              layoutId: snapshot.layoutId,
              fragments: fragments,
              compactHeight: true,
              onSourceTap: (_, position) {
                if (position.isExact) hits.add(position.sourceRune);
              },
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(key)), cell.contentBounds.size);
    await tester.tapAt(tester.getTopLeft(find.byKey(key)) + point);
    expect(hits, hasLength(1));
    expect(
      hits.single,
      inInclusiveRange(
        cell.element.source.runeStart,
        cell.element.source.runeEnd,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(cache.activeLeases, 0);
  });

  test('real width probes feed columns and wrapping feeds height', () {
    final document = _parse(
      '<table cellspacing="0" cellpadding="3" style="max-width:300px">'
      '<tr><td>aaaa bb</td><td>cccc dd</td></tr></table>',
    );
    final cache = _cache();
    for (final (available, used) in [
      (120.0, 120.0),
      (80.0, 92.0),
      (500.0, 152.0),
    ]) {
      final layout = _layout(
        _start(document, cache, availableWidth: available),
      );
      expect(layout.size.width, closeTo(used, 0.001));
      expect(layout.size.height, closeTo(available > 120 ? 16 : 26, 0.001));
      expect(cache.activeLeases, 0);
      for (final area in layout.cells) {
        final delivery = _open(area);
        expect(delivery.single.lines.length, available > 120 ? 1 : 2);
        expect(area.snapshot.identity, document.identity);
        expect(area.snapshot.width, closeTo(used / 2 - 6, 0.001));
        for (final fragment in delivery) {
          fragment.close();
        }
      }
      expect(cache.activeLeases, 0);
      layout.close();
    }
  });

  test(
    'merged grid combines actual Ruby, frozen image, captions and row geometry',
    () {
      final document = _parse(
        '<table width="168" cellpadding="2" bgcolor="#f5f5f5" dir="rtl" '
        'style="border-spacing:3px 4px">'
        '<caption style="caption-side:bottom">cap</caption>'
        '<colgroup><col width="64"><col width="48"><col width="40"></colgroup>'
        '<tr bgcolor="#abc" height="32">'
        '<td rowspan="2"><ruby>A<rt>aa</rt></ruby>'
        '<img width="32" height="16" src="https://example.invalid/one.png"></td>'
        '<td colspan="2"><a href="/thread">link</a></td></tr>'
        '<tr><td>text</td><td>tail</td></tr></table>',
      );
      final cache = _cache();
      final requests = <ForumBodyElement>[];
      final layout = _layout(
        _start(
          document,
          cache,
          images: (identity, image) {
            requests.add(image);
            final raw = image.resource!.rawSource!;
            return ForumBodyImageInput(
              identity: identity,
              element: image,
              entry: ForumHtmlReadableImageEntry(
                index: 0,
                url: raw,
                rawSrc: raw,
                resource: const _Resource(),
              ),
              layout: const ForumHtmlImageLayout(aspectRatio: 2),
            );
          },
        ),
      );
      final first = layout.cells.first;
      expect(requests, [same(document.imageElements.single)]);
      expect(layout.size.width, 168);
      expect(layout.gridTop, 0);
      expect(layout.captions.single.bounds.top, layout.geometry.size.height);
      expect(layout.captions.single.bounds.bottom, layout.size.height);
      expect(layout.rowBackgrounds, [const Color(0xffaabbcc), null]);
      expect(
        layout.geometry.rowBounds(1).top - layout.geometry.rowBounds(0).bottom,
        4,
      );
      expect(first.bounds.right, 168);
      expect(first.bounds.height, layout.geometry.size.height);
      expect(first.element, same(document.nodeAtPath(first.element.path)));
      expect(first.contentBounds.left, first.bounds.left + 2);
      expect(
        first.snapshot.single.fragments.last.imageFrame!.imageRect.size,
        const Size(32, 16),
      );
      expect(cache.activeLeases, 0);

      final delivery = _open(first);
      expect(delivery.first, isA<ForumBodyPreparedInlineFragment>());
      expect(delivery.first.projection.text, 'Aaa');
      expect(
        (delivery.last as ForumBodyPreparedImageFragment).content.input.element,
        same(requests.single),
      );
      expect(cache.activeLeases, greaterThan(0));
      layout.close();
      expect(delivery.every((fragment) => !fragment.isActive), isTrue);
      expect(cache.activeLeases, 0);
    },
  );

  test('cancel and aggregate exhaustion retire child sessions and leases', () {
    final document = _parse(
      '<table><tr><td>first</td><td>second</td></tr></table>',
    );
    final cache = _cache();
    final pending = _start(document, cache);
    for (var i = 0; i < 300 && cache.layoutBuildCount == 0; i++) {
      pending.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    }
    expect(cache.layoutBuildCount, greaterThan(0));
    pending.close();
    expect(cache.activeLeases, 0);
    expect(pending.takeLayout, throwsStateError);

    final tooSmall = _start(
      document,
      cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 8,
        maxFragments: 8,
        maxParagraphs: 1,
        maxTextCodeUnits: 1024,
        maxRuns: 128,
        maxIssuedLeases: 16,
      ),
    );
    expect(
      () => _layout(tooSmall),
      throwsA(
        isA<ForumBodyTableException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyTableFailure.workLimit,
        ),
      ),
    );
    expect(cache.activeLeases, 0);
  });
}
