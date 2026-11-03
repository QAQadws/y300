import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/emphasis_allocation_fixture.dart';

ForumBodyParagraphCache _cache([int count = 32]) {
  final result = ForumBodyParagraphCache(
    maxEntries: count,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(result.close);
  return result;
}

ForumBodyEmphasisParagraphNativeEntries _index(
  ForumBodyEmphasisParagraphMetrics paragraph,
  ForumBodyParagraphCache cache,
) {
  final job = ForumBodyEmphasisParagraphNativeEntriesPreparation(
    paragraph: paragraph,
    cache: cache,
    ensureOwner: () {},
  );
  while (!job.isReady) {
    job.advance(maxParts: 32);
  }
  return job.take();
}

ForumBodyEmphasisParagraphNativeEntries _entries({
  String? body,
  double width = 1,
}) {
  final f = body == null
      ? EmphasisAllocationFixture(width: width)
      : EmphasisAllocationFixture(width: width, body: body);
  final job = ForumBodyEmphasisParagraphPreparation(
    content: f.glyphs.original,
    cache: f.cache,
    ensureOwner: () {},
    width: width,
  );
  while (!job.isReady) {
    job.advance(maxParts: 32);
  }
  final paragraph = job.takeMetrics();
  f.cache.close();
  return _index(paragraph, _cache());
}

ForumBodyTextPageComposer _composer(
  ForumBodyEmphasisParagraphNativeEntries entries, {
  double height = 100000,
  int? nativeEntries,
  int? bytes,
  int? handles,
}) {
  final result = ForumBodyTextPageComposer(
    identity: entries.paragraph.content.identity,
    layoutId: 'emphasis-layout',
    width: entries.paragraph.width,
    height: height,
    maxPages: 100,
    maxFragments: 1000,
    maxNativeEntriesPerPage: nativeEntries,
    maxNativeEstimatedBytesPerPage: bytes,
    maxNativeHandlesPerPage: handles,
  );
  addTearDown(result.close);
  return result;
}

void _append(
  ForumBodyTextPageComposer composer,
  ForumBodyEmphasisParagraphNativeEntries entries, {
  int index = 0,
  void Function()? guard,
  ForumBodyParagraphWindow window = ForumBodyParagraphWindow.full,
}) {
  composer.appendEmphasis(
    entries: entries,
    ensureOwner: guard ?? () {},
    paragraphIndex: index,
    left: 0,
    spaceBefore: 0,
    spaceAtPageStart: 0,
    window: window,
  );
}

void _drain(ForumBodyTextPageComposer composer) {
  for (var n = 0; !composer.needsInput && n < 50000; n++) {
    final step = composer.advance(maxLines: 1);
    expect(step.linesInspected, lessThanOrEqualTo(1));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
  }
  expect(composer.needsInput, isTrue);
}

ForumBodyEmphasisFragmentInput _fragment(
  ForumBodyEmphasisParagraphMetrics paragraph,
  int start,
  int end,
) {
  final job = ForumBodyEmphasisFragmentInputPreparation(
    paragraph: paragraph,
    startLine: start,
    endLine: end,
    ensureOwner: () {},
  );
  while (!job.isReady) {
    job.advance(maxParts: 32);
  }
  return job.takeInput();
}

int _exactBytes(ForumBodyEmphasisParagraphNativeEntries entries) {
  final fonts = {
    for (final cost in entries.fontCostsInLines(
      0,
      entries.paragraph.lines.length,
    ))
      cost.identity: cost.estimatedBytes,
  };
  return fonts.values.fold<int>(0, (n, v) => n + v) +
      _fragment(
        entries.paragraph,
        0,
        entries.paragraph.lines.length,
      ).pictureInput.estimatedBytes;
}

({
  List<ForumBodyParagraphContent> contents,
  List<ForumBodyEmphasisParagraphNativeEntries?> emphasis,
})
_chapter(List<String> bodies, Set<int> emphasisIndices) {
  final doc = const ForumBodyParser().parse(
    html: [
      for (var i = 0; i < bodies.length; i++)
        '<p style="white-space:pre-wrap;line-height:.4;'
            'text-emphasis:${emphasisIndices.contains(i) ? "'X' red" : 'none'}">${bodies[i]}</p>',
    ].join(),
    sourceId: 'emphasis-mixed-chapter',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    doc,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: Color(0xff123456),
      ),
      fontRevision: 'mixed-chapter-ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  final contents = [
    for (var i = 0; i < bodies.length; i++)
      const ForumBodyParagraphContentBuilder().build(
        document: doc,
        styles: styles,
        path: '$i',
      ),
  ];
  final result = <ForumBodyEmphasisParagraphNativeEntries?>[];
  for (var i = 0; i < contents.length; i++) {
    if (!emphasisIndices.contains(i)) {
      result.add(null);
      continue;
    }
    final cache = _cache(),
        measure = ForumBodyEmphasisParagraphPreparation(
          content: contents[i],
          cache: cache,
          ensureOwner: () {},
          width: 1,
        );
    while (!measure.isReady) {
      measure.advance(maxParts: 32);
    }
    final paragraph = measure.takeMetrics();
    cache.close();
    result.add(_index(paragraph, _cache()));
  }
  return (contents: contents, emphasis: result);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  test(
    'one growing fragment reserves five shared fonts plus ONE scene with exact bytes',
    () {
      final entries = _entries(body: 'AAAA'),
          composer = _composer(
            entries,
            nativeEntries: 6,
            bytes: _exactBytes(entries),
            handles: 2,
          );
      _append(composer, entries);
      _drain(composer);
      composer.finish();
      final fragment = composer.snapshot.single.fragments.single;
      expect(fragment.kind, ForumBodyTextPageFragmentKind.emphasis);
      expect(fragment.startLine, 0);
      expect(fragment.endLine, entries.paragraph.lines.length);
      expect(fragment.coverageStartUtf16, 0);
      expect(fragment.coverageEndUtf16, 4);
      expect(fragment.sourceHint, (runeStart: 0, runeEnd: 4));
      expect(fragment.height, entries.paragraph.height);
      expect(composer.snapshot.composerRevision, 12);
      final actual = _fragment(
        entries.paragraph,
        fragment.startLine,
        fragment.endLine,
      );
      final cache = _cache(6);
      final visible = ForumBodyEmphasisFragmentPreparation(
        input: actual,
        cache: cache,
        ensureOwner: () {},
        width: actual.width,
        expectedTextScaler: entries.paragraph.textScaler,
      );
      while (!visible.isReady) {
        visible.advance(maxParts: 32);
      }
      final view = visible.takeLayout();
      expect(view.height, fragment.height);
      expect(view.coverageEndUtf16, fragment.coverageEndUtf16);
      expect(view.nativeLeases, hasLength(2));
      view.close();
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'next group exceeding byte reservation seals a stable prefix and starts a fresh scene',
    () {
      final entries = _entries(body: 'AAAA'),
          composer = _composer(
            entries,
            nativeEntries: 6,
            bytes: _exactBytes(entries) - 1,
            handles: 2,
          );
      _append(composer, entries);
      ForumBodyTextPageSnapshot? prefix;
      while (!composer.needsInput) {
        composer.advance(maxLines: 1);
        if (composer.snapshot.isNotEmpty) {
          prefix ??= composer.snapshot;
        }
      }
      composer.finish();
      expect(composer.snapshot, hasLength(2));
      expect(prefix, hasLength(1));
      expect(prefix!.isComplete, isFalse);
      expect(prefix.single.fragments.single.endLine, 3);
      final fragments = composer.snapshot.expand((p) => p.fragments).toList();
      expect(fragments.map((f) => f.startLine), [0, 3]);
      expect(fragments.map((f) => f.endLine), [3, 4]);
      expect(fragments.map((f) => f.coverageStartUtf16), [0, 3]);
      expect(fragments.map((f) => f.coverageEndUtf16), [3, 4]);
    },
  );
  test(
    'minimum complete scene entry/byte/handle budgets reject without native work',
    () {
      final entries = _entries(body: 'A');
      for (final (composer, failure) in [
        (
          _composer(entries, nativeEntries: 5),
          ForumBodyTextPageFailure.nativeEntryLimit,
        ),
        (
          _composer(entries, bytes: _exactBytes(entries) - 1),
          ForumBodyTextPageFailure.nativeByteLimit,
        ),
        (
          _composer(entries, handles: 1),
          ForumBodyTextPageFailure.nativeHandleLimit,
        ),
      ]) {
        _append(composer, entries);
        expect(
          () => _drain(composer),
          throwsA(
            isA<ForumBodyTextPageException>().having(
              (e) => e.failure,
              'failure',
              failure,
            ),
          ),
        );
        expect(composer.snapshot, isEmpty);
        expect(composer.isClosed, isTrue);
      }
    },
  );
  test(
    'only complete grapheme groups paginate and every planned page binds current source',
    () {
      final entries = _entries(),
          paragraph = entries.paragraph,
          height = paragraph.groups.map((g) => g.height).reduce(math.max),
          composer = _composer(entries, height: height);
      _append(composer, entries);
      _drain(composer);
      composer.finish();
      var end = 0;
      final cache = _cache();
      for (final page in composer.snapshot) {
        final fragment = page.fragments.single;
        expect(fragment.coverageStartUtf16, end);
        expect(paragraph.lines[fragment.startLine].canBreakBefore, isTrue);
        expect(paragraph.lines[fragment.endLine - 1].canBreakAfter, isTrue);
        final expected = paragraph.fragment(
          fragment.startLine,
          fragment.endLine,
        );
        expect(fragment.height, expected.height);
        expect(fragment.height, lessThanOrEqualTo(height));
        final job = ForumBodyEmphasisFragmentPreparation(
          input: _fragment(paragraph, fragment.startLine, fragment.endLine),
          cache: cache,
          ensureOwner: () {},
          width: paragraph.width,
          expectedTextScaler: paragraph.textScaler,
        );
        while (!job.isReady) {
          job.advance(maxParts: 32);
        }
        final view = job.takeLayout();
        expect(view.coverageStartUtf16, fragment.coverageStartUtf16);
        expect(view.coverageEndUtf16, fragment.coverageEndUtf16);
        expect(view.height, fragment.height);
        view.close();
        end = fragment.coverageEndUtf16;
      }
      expect(end, paragraph.content.projection.text.length);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'scene group capacity seals pages even with otherwise unlimited geometry',
    () {
      final entries = _entries(body: 'A' * 600), composer = _composer(entries);
      _append(composer, entries);
      _drain(composer);
      composer.finish();
      expect(composer.snapshot, hasLength(2));
      expect(composer.snapshot[0].fragments.single.endLine, 512);
      expect(composer.snapshot[1].fragments.single.startLine, 512);
      expect(composer.snapshot[1].fragments.single.endLine, 600);
    },
  );
  test(
    'command capacity splits large mark groups before final scene construction',
    () {
      final entries = _entries(body: ('${'A' * 500}\n') * 17, width: 10000),
          composer = _composer(entries);
      _append(composer, entries);
      _drain(composer);
      composer.finish();
      expect(composer.snapshot, hasLength(2));
      expect(composer.snapshot[0].fragments.single.endLine, 16);
      expect(composer.snapshot[1].fragments.single.startLine, 16);
      expect(
        composer.snapshot[1].fragments.single.endLine,
        entries.paragraph.lines.length,
      );
      for (final page in composer.snapshot) {
        final f = page.fragments.single;
        expect(
          _fragment(
            entries.paragraph,
            f.startLine,
            f.endLine,
          ).pictureInput.commands.length,
          lessThanOrEqualTo(
            ForumBodyEmphasisFragmentInputPreparation.defaultMaxCommands,
          ),
        );
      }
    },
  );
  for (final emphasisFirst in [false, true]) {
    for (final entryLimit in [6, 7]) {
      test(
        'ordinary/emphasis page shares ledger in both orders $emphasisFirst limit=$entryLimit',
        () {
          final at = emphasisFirst ? 0 : 1,
              chapter = _chapter(
                emphasisFirst ? ['AAAA', 'B'] : ['B', 'AAAA'],
                {at},
              ),
              entries = chapter.emphasis[at]!,
              cache = _cache(),
              ordinary = cache.acquire(
                content: chapter.contents[1 - at],
                width: 1,
              ),
              composer = _composer(
                entries,
                nativeEntries: entryLimit,
                bytes:
                    _exactBytes(entries) + ordinary.nativeLayoutEstimatedBytes,
                handles: 3,
              );
          for (var i = 0; i < 2; i++) {
            if (i == at) {
              _append(composer, entries, index: i);
            } else {
              composer.append(
                lease: ordinary,
                paragraphIndex: i,
                left: 0,
                spaceBefore: 0,
                spaceAtPageStart: 0,
              );
            }
            _drain(composer);
          }
          composer.finish();
          expect(composer.snapshot.length, entryLimit == 6 ? 2 : 1);
          expect(
            composer.snapshot
                .expand((p) => p.fragments)
                .map((f) => f.paragraphIndex),
            [0, 1],
          );
          expect(cache.activeLeases, 0);
        },
      );
    }
  }
  test(
    'distinct paragraph scenes reserve separately while sharing the actual marker font',
    () {
      final chapter = _chapter(['AAAA', 'CCCC'], {0, 1});
      for (final limit in [10, 11]) {
        final composer = _composer(
          chapter.emphasis.first!,
          nativeEntries: limit,
          handles: 4,
        );
        for (var i = 0; i < 2; i++) {
          _append(composer, chapter.emphasis[i]!, index: i);
          _drain(composer);
        }
        composer.finish();
        expect(composer.snapshot.length, limit == 10 ? 2 : 1);
      }
    },
  );
  test(
    'real zero-text terminal window keeps its own line and scene without a source hint',
    () {
      final entries = _entries(body: 'A\n', width: 140);
      expect(entries.paragraph.hasTerminalEmptyLine, isTrue);
      for (final window in [
        ForumBodyParagraphWindow.beforeTerminalEmptyLine,
        ForumBodyParagraphWindow.terminalEmptyLine,
      ]) {
        final composer = _composer(
          entries,
          nativeEntries: window == ForumBodyParagraphWindow.terminalEmptyLine
              ? 5
              : 6,
          handles: 2,
        );
        _append(composer, entries, window: window);
        _drain(composer);
        composer.finish();
        final fragment = composer.snapshot.single.fragments.single;
        if (window == ForumBodyParagraphWindow.terminalEmptyLine) {
          expect(fragment.coverageStartUtf16, 2);
          expect(fragment.coverageEndUtf16, 2);
          expect(fragment.sourceHint, isNull);
        } else {
          expect(fragment.coverageStartUtf16, 0);
          expect(fragment.coverageEndUtf16, 2);
        }
      }
    },
  );
  test(
    'host retirement rejects pending input while preserving sealed numeric prefix',
    () {
      final entries = _entries(body: 'AAAA'),
          composer = _composer(
            entries,
            height: entries.paragraph.groups.first.height,
          );
      var active = true;
      _append(
        composer,
        entries,
        guard: () {
          if (!active) throw StateError('Retired');
        },
      );
      while (composer.snapshot.isEmpty) {
        composer.advance(maxLines: 1);
      }
      final prefix = composer.snapshot;
      active = false;
      expect(() => composer.advance(maxLines: 1), throwsStateError);
      expect(composer.isClosed, isTrue);
      expect(composer.snapshot, hasLength(1));
      expect(composer.snapshot.single, same(prefix.single));
      final closedDuringAppend = _composer(entries);
      expect(
        () => _append(
          closedDuringAppend,
          entries,
          guard: closedDuringAppend.close,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'numeric emphasis does not masquerade as an ordinary paragraph binding',
    () {
      final entries = _entries(body: 'A'), composer = _composer(entries);
      _append(composer, entries);
      _drain(composer);
      composer.finish();
      final cache = _cache(),
          lease = cache.acquire(
            content: entries.paragraph.glyphInput.glyphs,
            width: entries.paragraph.width,
          );
      expect(
        () => ForumBodyParagraphPageContent(
          lease.content,
        ).nativeHandleCountFor(composer.snapshot.single.fragments.single),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      lease.release();
      final empty = _entries(body: ''), emptyComposer = _composer(empty);
      expect(() => _append(emptyComposer, empty), throwsArgumentError);
    },
  );
}
