import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _html =
    '<p>outside</p><div style="font-size:24px;color:#334455">'
    '<table><caption>Caption</caption><tbody><tr>'
    '<td colspan="2" dir="rtl" style="font-size:0.75em"><a href="/thread">link</a> '
    '<ruby>A<rt>aa</rt></ruby>'
    '<p style="width:50%">end</p><img src="https://example.invalid/one.png">'
    '</td><td>other<img src="https://example.invalid/two.png"></td>'
    '</tr></tbody></table></div><p>after</p>';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
  fontRevision: 'table-cell',
  linkColor: const Color(0xff1122cc),
  paragraphAfter: 0,
  policy: ForumBodyStylePolicy({
    ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
  }),
);

ForumBodyDocument _parse([String html = _html]) => const ForumBodyParser()
    .parse(html: html, sourceId: 'table-cell', conversionIdentity: 'none');

ForumBodyTableGrid _grid(ForumBodyDocument document) =>
    ForumBodyTableGrid.fromDocument(document, document.tableElements.single);

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource(this.cacheKey);
  @override
  final String cacheKey;
}

ForumBodyTextPageSession _open(
  ForumBodyDocument document,
  ForumBodyElement root,
  ForumBodyParagraphCache cache,
  List<ForumBodyElement> requests, {
  ForumBodyCollapseLayout? collapses,
  double width = 160,
  double? intrinsicAvailableWidth,
}) => ForumBodyTextPageSession(
  document: document,
  contentRoot: root,
  intrinsicAvailableWidth: intrinsicAvailableWidth,
  collapses: collapses,
  reader: _reader,
  cache: cache,
  limits: const ForumBodyTextPageSessionLimits(
    maxPages: 4,
    maxFragments: 32,
    maxParagraphs: 32,
    maxTextCodeUnits: 4096,
    maxRuns: 128,
    maxIssuedLeases: 24,
  ),
  layoutId: root.path,
  width: width,
  height: 240,
  imageResolver: (identity, element) {
    requests.add(element);
    final raw = element.resource!.rawSource!;
    return ForumBodyImageInput(
      identity: identity,
      element: element,
      entry: ForumHtmlReadableImageEntry(
        index: requests.length - 1,
        url: raw,
        rawSrc: raw,
        resource: _Resource(element.path),
      ),
      layout: const ForumHtmlImageLayout(aspectRatio: 4),
    );
  },
);

void _finish(ForumBodyTextPageSession session) {
  for (var i = 0; !session.isComplete && i < 2000; i++) {
    final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(step.eventsRead, lessThanOrEqualTo(1));
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
  expect(session.isComplete, isTrue);
}

List<ForumBodyPreparedTextFragment> _prepare(ForumBodyTextPageSession session) {
  final job = session.openPagePreparation(0);
  try {
    for (var i = 0; !job.isReady && i < 2000; i++) {
      final step = job.advance(maxFragments: 1, maxParts: 1);
      expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
    }
    return job.takeFragments();
  } finally {
    job.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'wide native probes report content widths and preserve a sized image',
    () {
      final document = _parse(
        '<table><tr><td>'
        '<p style="padding:4px">aaaa bb</p>'
        '<img width="26" height="13" src="https://example.invalid/one.png">'
        '</td></tr></table>',
      );
      final root = _grid(document).cells.single.element;
      final cache = ForumBodyParagraphCache(
        maxEntries: 24,
        maxEstimatedBytes: 1 << 22,
      );
      addTearDown(cache.close);
      for (final probe in [160.0, 1000.0]) {
        final session = _open(
          document,
          root,
          cache,
          [],
          width: probe,
          intrinsicAvailableWidth: 160,
        );
        try {
          expect(session.intrinsicWidths, isNull);
          _finish(session);
          final widths = session.intrinsicWidths!;
          expect(widths.minimum, closeTo(48, 0.001));
          expect(widths.preferred, closeTo(78, 0.001));
          expect(
            session.snapshot.single.fragments.last.imageFrame!.imageRect.width,
            26,
          );
          expect(cache.activeLeases, 0);
        } finally {
          session.close();
        }
      }
    },
  );

  test('a real merged-grid cell uses native text, ruby and image delivery', () {
    final document = _parse();
    final grid = _grid(document);
    final root = grid.cells.first.element;
    expect(grid.cells.first.columnSpan, 2);
    final requests = <ForumBodyElement>[];
    final cache = ForumBodyParagraphCache(
      maxEntries: 24,
      maxEstimatedBytes: 1 << 22,
    );
    addTearDown(cache.close);
    final session = _open(document, root, cache, requests);
    addTearDown(session.close);
    _finish(session);
    final page = session.snapshot.single;
    expect(session.snapshot.identity, document.identity);
    expect(requests, [same(document.imageElements.first)]);
    expect(page.fragments.first.path, root.path);
    expect(page.fragments[1].left, 80);
    expect(page.fragments[1].width, 80);
    expect(page.fragments.last.path, requests.single.path);
    final delivered = _prepare(session);
    try {
      final mixed = delivered.first as ForumBodyPreparedInlineFragment;
      expect(mixed.projection.text, 'link Aaa');
      final link = mixed.runs.firstWhere((run) => run.style.linkTarget != null);
      expect(link.style.linkTarget, '/thread');
      expect(link.style.textStyle.fontFamily, 'Ahem');
      expect(link.style.textStyle.fontSize, 18);
      expect(link.style.textDirection, TextDirection.rtl);
      final glyph = mixed.glyphBoxes(0, 1).first;
      final hit = mixed.view.sourceAt(glyph.toRect().center);
      final originalLinkText =
          (root.children.first as ForumBodyElement).children.single
              as ForumBodyText;
      expect(hit.isExact, isTrue);
      expect(
        hit.sourceRune,
        inInclusiveRange(
          originalLinkText.source.runeStart,
          originalLinkText.source.runeEnd,
        ),
      );
      final annotation = document.descendants
          .whereType<ForumBodyElement>()
          .singleWhere((node) => node.kind == ForumBodyElementKind.rubyText);
      final annotationHit = mixed.view.sourceAt(
        mixed.glyphBoxes(6, 7).first.toRect().center,
      );
      expect(annotationHit.isExact, isTrue);
      expect(
        annotationHit.sourceRune,
        inInclusiveRange(
          annotation.source.runeStart,
          annotation.source.runeEnd,
        ),
      );
      expect(delivered[1].projection.text, 'end');
      final image = delivered.last as ForumBodyPreparedImageFragment;
      expect(image.content.input.element, same(requests.single));
      expect(image.projection.text, isEmpty);
    } finally {
      for (final delivery in delivered) {
        delivery.close();
      }
    }
    expect(cache.activeLeases, 0);
  });

  test('caption and cell views inherit only their actual ancestry', () {
    final document = _parse();
    final grid = _grid(document);
    final styles = const ForumBodyStyleResolver().resolve(document, _reader);
    for (final root in [
      grid.captions.single,
      ...grid.cells.map((cell) => cell.element),
    ]) {
      final cursor = const ForumBodyStyleResolver().open(
        document,
        _reader,
        contentRoot: root,
      );
      addTearDown(cursor.close);
      final scoped = styles.byPath[root.path]!;
      expect(cursor.root.textStyle, scoped.textStyle);
      expect(cursor.root.textDirection, scoped.textDirection);
      final actual = <ForumBodyNode>[];
      while (cursor.moveNext()) {
        final node = cursor.currentNode!;
        actual.add(node);
        final original = styles.byPath[node.path]!;
        expect(cursor.currentStyle!.textStyle, original.textStyle);
        expect(cursor.currentStyle!.role, original.role);
        expect(cursor.currentStyle!.linkTarget, original.linkTarget);
      }
      expect(
        actual,
        orderedEquals(
          document.descendants.where(
            (node) => node.path.startsWith('${root.path}/'),
          ),
        ),
      );
    }
    expect(
      () => const ForumBodyStyleResolver().open(
        document,
        _reader,
        contentRoot: _grid(_parse()).cells.first.element,
      ),
      throwsArgumentError,
    );
  });

  test('scoped cells cannot revive hidden or closed ancestors', () {
    for (final (prefix, suffix) in [
      ('<div style="display:none">', '</div>'),
      (
        '<div class="showcollapse_box"><div class="showcollapse_title">Title</div>'
            '<div class="showcollapse_content" style="display:none">',
        '</div></div>',
      ),
    ]) {
      final document = _parse(
        '$prefix<table><tr><td><img src="/hidden.png">secret</td></tr></table>$suffix',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      final requests = <ForumBodyElement>[];
      final session = _open(
        document,
        _grid(document).cells.single.element,
        cache,
        requests,
        collapses: ForumBodyCollapseLayout(document),
      );
      try {
        _finish(session);
        expect(requests, isEmpty);
        expect(session.snapshot, isEmpty);
        expect(session.resolvedNodeCount, 0);
      } finally {
        session.close();
        cache.close();
      }
    }
  });
}
