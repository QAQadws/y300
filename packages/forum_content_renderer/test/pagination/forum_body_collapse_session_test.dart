import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _html =
    '<p>before</p>'
    '<div class="showcollapse_box" id="duplicate">'
    '<div class="showcollapse_title">same title</div>'
    '<div class="showcollapse_content" style="display:none">'
    '<p>outer text</p>'
    '<div class="showcollapse_box showcollapse_active" id="duplicate">'
    '<div class="showcollapse_title">same title</div>'
    '<div class="showcollapse_content" style="display:none">'
    '<p>inner text</p><img src="https://example.invalid/fold.png">'
    '<div class="showcollapse_gather">mechanical control</div>'
    '</div></div></div></div>'
    '<p>after</p>';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
  fontRevision: 'fold-test',
  linkColor: const Color(0xff0000ff),
  paragraphBefore: 0,
  paragraphAfter: 0,
);

ForumBodyDocument _parse() => const ForumBodyParser().parse(
  html: _html,
  sourceId: 'collapse-session',
  conversionIdentity: 'none',
);

ForumBodyTextPageSession _session(
  ForumBodyDocument document,
  ForumBodyParagraphCache cache,
  ForumBodyCollapseLayout collapses,
  List<ForumBodyElement> imageRequests,
) => ForumBodyTextPageSession(
  document: document,
  reader: _reader,
  cache: cache,
  limits: const ForumBodyTextPageSessionLimits(
    maxPages: 30,
    maxFragments: 100,
    maxParagraphs: 100,
    maxTextCodeUnits: 30000,
    maxRuns: 1000,
    maxIssuedLeases: 16,
  ),
  layoutId: 'collapse-session',
  width: 180,
  height: 80,
  collapses: collapses,
  imageResolver: (identity, element) {
    imageRequests.add(element);
    return ForumBodyImageInput(
      identity: identity,
      element: element,
      entry: ForumHtmlReadableImageEntry(
        index: 0,
        url: element.resource!.rawSource!,
        rawSrc: element.resource!.rawSource!,
        resource: const _Resource(),
      ),
      layout: const ForumHtmlImageLayout(aspectRatio: 3),
    );
  },
);

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource();
  @override
  String get cacheKey => 'fold-image';
}

List<String> _renderedText(ForumBodyTextPageSession session) {
  for (var i = 0; !session.isComplete && i < 5000; i++) {
    final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(step.eventsRead, lessThanOrEqualTo(1));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
  }
  expect(session.isComplete, isTrue);
  final text = <String>[];
  for (var page = 0; page < session.snapshot.length; page++) {
    final job = session.openPagePreparation(page);
    try {
      for (var i = 0; !job.isReady && i < 1000; i++) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      final prepared = job.takeFragments();
      for (final fragment in prepared) {
        if (fragment.projection.text.isNotEmpty) {
          text.add(fragment.projection.text);
        }
        fragment.close();
      }
    } finally {
      job.close();
    }
  }
  return text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'nested folds only deliver their frozen visible sources in the Session',
    () {
      final document = _parse();
      final cache = ForumBodyParagraphCache(
        maxEntries: 16,
        maxEstimatedBytes: 1 << 22,
      );
      addTearDown(cache.close);
      final defaults = ForumBodyCollapseLayout(document);
      expect(defaults.sections, hasLength(2));
      final outer = defaults.sections.values.singleWhere(
        (fold) => !fold.expanded,
      );
      final inner = defaults.sections.values.singleWhere(
        (fold) => fold.expanded,
      );
      expect(outer.box.attributes['id'], inner.box.attributes['id']);
      expect(outer.id, isNot(inner.id));
      expect(document.nodeAtPath(inner.title.path), same(inner.title));
      final overrides = {outer.id: true};
      final both = ForumBodyCollapseLayout(
        document,
        expansionOverrides: overrides,
      );
      overrides[outer.id] = false;
      expect(both.sections[outer.id]!.expanded, isTrue);

      final layouts = [
        defaults,
        ForumBodyCollapseLayout(
          document,
          expansionOverrides: {outer.id: true, inner.id: false},
        ),
        both,
      ];
      final expected = [
        ['before', 'same title', 'after'],
        ['before', 'same title', 'outer text', 'same title', 'after'],
        [
          'before',
          'same title',
          'outer text',
          'same title',
          'inner text',
          'after',
        ],
      ];
      final tailHints = <Object?>[];
      for (final (index, layout) in layouts.indexed) {
        final requests = <ForumBodyElement>[];
        final session = _session(document, cache, layout, requests);
        try {
          expect(_renderedText(session), expected[index]);
          final fragments = session.snapshot.expand((page) => page.fragments);
          tailHints.add(
            fragments
                .singleWhere((fragment) => fragment.path == '2')
                .sourceHint,
          );
          expect(
            requests,
            index == 2 ? [document.imageElements.single] : isEmpty,
          );
          expect(cache.activeLeases, 0);
        } finally {
          session.close();
        }
      }
      expect(tailHints.toSet(), hasLength(1));
      expect(tailHints.first, isNotNull);
      expect(document.sourceText, contains('inner text'));
      expect(document.sourceText, contains('mechanical control'));
    },
  );

  test('a collapse layout cannot control an equal-value foreign document', () {
    final document = _parse(), other = _parse();
    final cache = ForumBodyParagraphCache(
      maxEntries: 8,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    expect(other.identity, document.identity);
    expect(
      () => _session(other, cache, ForumBodyCollapseLayout(document), []),
      throwsArgumentError,
    );
    expect(cache.activeLeases, 0);
  });
}
