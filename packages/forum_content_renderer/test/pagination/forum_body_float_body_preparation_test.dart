import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_float_body_preparation.dart';

const _limits = ForumBodyTextPageSessionLimits(
  maxPages: 12,
  maxFragments: 48,
  maxParagraphs: 48,
  maxTextCodeUnits: 2048,
  maxRuns: 128,
  maxIssuedLeases: 8,
);

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
  fontRevision: 'float-body',
  linkColor: const Color(0xff0000ff),
  paragraphAfter: 0,
);

({ForumBodyDocument document, ForumBodyInlineFlowFloat source}) _input(
  String html,
) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'float-body',
    conversionIdentity: 'none',
  );
  final cursor = ForumBodyTextFlowCursor(
    document: document,
    reader: _reader,
    captureFloats: true,
  );
  try {
    while (!cursor.isComplete) {
      cursor.advance(maxEvents: 1);
      final unit = cursor.current;
      if (unit is ForumBodyTextFlowInline) {
        return (
          document: document,
          source: unit.content.parts
              .whereType<ForumBodyInlineFlowFloat>()
              .single,
        );
      }
    }
    fail('Missing float input');
  } finally {
    cursor.close();
  }
}

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 16,
    maxEstimatedBytes: 1 << 20,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyFloatBodyPreparation _open(
  ({ForumBodyDocument document, ForumBodyInlineFlowFloat source}) input,
  ForumBodyParagraphCache cache,
  double containingWidth, {
  ForumBodyImageResolver? imageResolver,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final job = ForumBodyFloatBodyPreparation(
    document: input.document,
    source: input.source,
    reader: _reader,
    cache: cache,
    containingWidth: containingWidth,
    layoutId: 'float-body',
    limits: _limits,
    imageResolver: imageResolver,
    textScaler: textScaler,
  );
  addTearDown(job.close);
  return job;
}

ForumBodyFloatBodyLayout _finish(ForumBodyFloatBodyPreparation job) {
  for (var i = 0; i < 1000 && !job.isReady; i++) {
    final step = job.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
  }
  expect(job.isReady, isTrue);
  final layout = job.takeLayout();
  addTearDown(layout.close);
  return layout;
}

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource();

  @override
  String get cacheKey => 'float-body-image';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'auto width uses actual native min/preferred widths and its side margin',
    () {
      final input = _input(
        '<span style="float:left;margin-right:5px">aa aa</span>',
      );
      final cache = _cache();
      for (final (available, width, height) in [
        (120.0, 50.0, 10.0),
        (38.0, 33.0, 20.0),
        (16.0, 20.0, 20.0),
      ]) {
        final layout = _finish(_open(input, cache, available));
        expect(layout.source.element, same(input.source.element));
        expect(layout.margin, const EdgeInsets.only(right: 5));
        expect(layout.borderBoxSize, Size(width, height));
        expect(layout.occupiedSize, Size(width + 5, height));
        expect(layout.snapshot.width, width);
        expect(layout.snapshot.identity, input.document.identity);
        expect(layout.pageTop(0), 0);
        expect(layout.snapshot.single.usedHeight, height);
      }
      final scaled = _finish(
        _open(input, cache, 120, textScaler: const TextScaler.linear(2)),
      );
      expect(scaled.borderBoxSize, const Size(100, 20));
    },
  );

  test('specified width, box sizing and insets use the containing width', () {
    final input = _input(
      '<span style="float:right;width:50%;max-width:45px;min-width:60px;'
      'box-sizing:border-box;padding:3px 4px;margin:2px 3px 4px 5px;'
      'height:30px">aa</span>',
    );
    final cache = _cache();
    final layout = _finish(_open(input, cache, 100));
    expect(cache.layoutBuildCount, 1);
    expect(layout.margin, const EdgeInsets.fromLTRB(5, 2, 3, 4));
    expect(layout.contentBounds, const Rect.fromLTWH(4, 3, 52, 10));
    expect(layout.borderBoxSize, const Size(60, 30));
    expect(layout.occupiedSize, const Size(68, 36));
  });

  test('float body reuses one frozen image and retains source-bound pages', () {
    const url = 'https://example.test/float.png';
    final input = _input(
      '<span style="float:right;margin-left:5px"><img src="$url">aaaa</span>',
    );
    final cache = _cache();
    var calls = 0;
    final layout = _finish(
      _open(
        input,
        cache,
        100,
        imageResolver: (identity, image) {
          calls++;
          return ForumBodyImageInput(
            identity: identity,
            element: image,
            entry: const ForumHtmlReadableImageEntry(
              index: 0,
              url: url,
              rawSrc: url,
              resource: _Resource(),
            ),
            layout: const ForumHtmlImageLayout(displaySize: Size(24, 12)),
          );
        },
      ),
    );
    expect(calls, 1);
    expect(layout.occupiedSize, const Size(45, 22));
    final preparation = layout.openPagePreparation(0);
    addTearDown(preparation.close);
    for (var i = 0; i < 200 && !preparation.isReady; i++) {
      preparation.advance(maxFragments: 1, maxParts: 1);
    }
    final fragments = preparation.takeFragments();
    expect(fragments, hasLength(2));
    expect(fragments.every((fragment) => fragment.isActive), isTrue);
    expect(cache.activeLeases, greaterThan(0));
    layout.close();
    expect(fragments.every((fragment) => !fragment.isActive), isTrue);
    expect(cache.activeLeases, 0);
  });

  test('retiring the layout owner closes a partially measured float', () {
    final input = _input('<span style="float:left"><b>aa</b> aa</span>');
    final cache = _cache();
    final job = _open(input, cache, 100);
    job.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(job.isReady, isFalse);
    cache.close();
    expect(
      () => job.advance(maxEvents: 1, maxLines: 1),
      throwsA(
        isA<ForumBodyTextPageSessionException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyTextPageSessionFailure.ownerRetired,
        ),
      ),
    );
    expect(job.isClosed, isTrue);
    expect(cache.activeLeases, 0);
  });
}
