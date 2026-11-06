import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          final headers = [
            for (final page in session.snapshot)
              for (final fragment in page.fragments)
                if (fragment.collapseHeader case final header?)
                  (page: page, fragment: fragment, header: header),
          ];
          expect(headers.map((item) => item.header.id), [
            outer.id,
            if (index != 0) inner.id,
          ]);
          for (final item in headers) {
            final section = layout.sections[item.header.id]!;
            expect(item.header.titlePath, section.title.path);
            expect(item.header.expanded, section.expanded);
            expect(item.header.bounds.height, greaterThanOrEqualTo(40));
            expect(
              item.header.bounds.bottom,
              lessThanOrEqualTo(item.page.usedHeight),
            );
            expect(item.fragment.left, greaterThan(item.header.bounds.left));
            expect(item.fragment.sourceHint, isNotNull);
          }
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

  testWidgets('the prepared header toggles its actual fragment and retires', (
    tester,
  ) async {
    final document = _parse();
    final cache = ForumBodyParagraphCache(
      maxEntries: 8,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final layout = ForumBodyCollapseLayout(document);
    final session = _session(document, cache, layout, []);
    addTearDown(session.close);
    expect(_renderedText(session), ['before', 'same title', 'after']);
    final page = session.snapshot.first;
    final title = page.fragments.singleWhere(
      (item) => item.collapseHeader != null,
    );
    final prepared = session.preparePageFragments(0);
    final toggled = <ForumBodyTextPageFragment>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: ForumBodyTextPageSurface.prepared(
            snapshot: session.snapshot,
            pageIndex: 0,
            layoutId: 'collapse-session',
            fragments: prepared,
            collapseLabels: const ForumHtmlCollapseLabels(
              fallbackTitle: 'Fold',
              expandedSemanticsLabel: 'Close fold',
              collapsedSemanticsLabel: 'Open fold',
            ),
            onCollapseToggle: toggled.add,
          ),
        ),
      ),
    );
    final toggle = find.byKey(
      ValueKey(
        'forum-native-collapse-toggle-${title.collapseHeader!.id}-${title.paragraphIndex}',
      ),
    );
    expect(tester.getSize(toggle), title.collapseHeader!.bounds.size);
    final node = tester.getSemantics(find.bySemanticsLabel('Open fold'));
    final data = node.getSemanticsData();
    expect(node.rect.size, tester.getSize(toggle));
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isExpanded, ui.Tristate.isFalse);
    expect(data.flagsCollection.isToggled, ui.Tristate.none);
    expect(data.hasAction(ui.SemanticsAction.expand), isTrue);
    expect(data.hasAction(ui.SemanticsAction.collapse), isFalse);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, ui.SemanticsAction.expand);
    expect(toggled.removeLast(), same(title));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      node.getSemanticsData().flagsCollection.isFocused,
      ui.Tristate.isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(toggled.removeLast(), same(title));

    final onTap = tester.widget<InkWell>(toggle).onTap!;
    await tester.tap(toggle);
    expect(toggled.single, same(title));
    await tester.pumpWidget(const SizedBox.shrink());
    onTap();
    expect(toggled, hasLength(1));
    expect(cache.activeLeases, 0);
  });
}
