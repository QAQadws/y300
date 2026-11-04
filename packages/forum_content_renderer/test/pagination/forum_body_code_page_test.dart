import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Fixture {
  _Fixture(String html) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'code-pages',
      conversionIdentity: 'none',
    );
    reader = ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
      fontRevision: 'code-font',
      linkColor: const Color(0xff0000ff),
      firstLineIndent: const ForumBodyLength(2, ForumBodyLengthUnit.em),
    );
    cache = ForumBodyParagraphCache(maxEntries: 64, maxEstimatedBytes: 1 << 24);
    session = ForumBodyTextPageSession(
      document: document,
      reader: reader,
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 500,
        maxTextCodeUnits: 200000,
        maxRuns: 10000,
        maxIssuedLeases: 256,
      ),
      layoutId: 'code-pages',
      width: 180,
      height: height,
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }
  final double height = 50;
  late final ForumBodyDocument document;
  late final ForumBodyReaderStyle reader;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;

  void drain() {
    for (var i = 0; !session.isComplete; i++) {
      if (i > 100000) fail('code flow stalled');
      final step = session.advance(
        maxEvents: 1,
        maxLines: 1,
        maxFormatParts: 1,
      );
      expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(step.madeProgress, isTrue);
    }
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    try {
      for (var i = 0; !job.isReady; i++) {
        if (i > 10000) fail('code page preparation stalled');
        final step = job.advance(maxFragments: 1, maxParts: 1);
        expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
        expect(step.waitingForLayoutBudget, isFalse);
      }
      return job.takeFragments();
    } finally {
      job.close();
    }
  }

  String collectText() {
    final text = StringBuffer();
    for (var page = 0; page < session.snapshot.length; page++) {
      final bindings = prepare(page);
      try {
        for (final (i, binding) in bindings.indexed) {
          final fragment = session.snapshot[page].fragments[i];
          text.write(
            binding.projection.text.substring(
              fragment.coverageStartUtf16,
              fragment.coverageEndUtf16,
            ),
          );
        }
      } finally {
        for (final binding in bindings) {
          binding.close();
        }
      }
    }
    expect(cache.activeLeases, 0);
    return text.toString();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  test(
    'pre and inline code admit original whitespace and exact source mapping',
    () {
      for (final (html, expected) in [
        ('<pre>  a<span>  b</span>\n\tc </pre>', '  a  b\n\tc '),
        ('<p>before<code>  a  </code>after</p>', 'before  a  after'),
        (
          '<pre style="white-space:pre-line">  a<span>  b\n c</span> </pre>',
          'a b\nc',
        ),
      ]) {
        final f = _Fixture(html);
        final styles = const ForumBodyStyleResolver().resolve(
          f.document,
          f.reader,
        );
        final content = const ForumBodyParagraphContentBuilder().build(
          document: f.document,
          styles: styles,
          path: '0',
        );
        expect(content.projection.text, expected);
        expect(content.textSpan.toPlainText(), expected);
        final b = expected.indexOf('b');
        final position = content.projection.sourceAtUtf16(b);
        expect(position.isExact, isTrue);
        final source = f.document.descendants
            .whereType<ForumBodyText>()
            .firstWhere(
              (node) =>
                  node.source.runeStart <= position.sourceRune &&
                  node.source.runeEnd > position.sourceRune,
            );
        expect(
          source.text.runes.elementAt(
            position.sourceRune - source.source.runeStart,
          ),
          'b'.codeUnitAt(0),
        );
        f.drain();
        expect(f.collectText(), expected);
      }
    },
  );

  for (final hardBreak in [false, true]) {
    test(
      'pre code retains blank and terminal lines across bounded pages (BR: $hardBreak)',
      () {
        final content = '  first();\n\n${'word ' * 100}\n  tail();\n';
        final html =
            '<pre><code>${hardBreak ? content.replaceAll('\n', '<br>') : content}</code></pre>';
        final f = _Fixture(html);
        f.drain();
        expect(f.session.snapshot.length, greaterThan(2));
        expect(f.collectText(), content);
        expect(
          f.session.snapshot
              .expand((p) => p.fragments)
              .every((f) => f.listMarker == null),
          isTrue,
        );
      },
    );
  }

  test(
    'Discuz code line numbers remain source-free across continuation pages',
    () {
      final first = '  ${'first(); ' * 100}';
      const last = '\tlast();  ';
      final f = _Fixture(
        '<div class="blockcode"><div><ol><li><span>$first</span>'
        '</li><li></li><li>$last</li></ol></div></div>',
      );
      f.drain();
      expect(f.session.snapshot.length, greaterThan(2));
      expect(
        f.session.snapshot
            .expand((p) => p.fragments)
            .where((f) => f.listMarker != null),
        hasLength(3),
      );
      for (var page = 0; page < f.session.snapshot.length; page++) {
        final bindings = f.prepare(page);
        try {
          for (final b in bindings) {
            expect(
              b.runs.every((r) => r.style.role == ForumBodyTextRole.code),
              isTrue,
            );
            expect(
              b.runs.every((r) => r.style.textStyle.fontFamily == 'monospace'),
              isTrue,
            );
            final body = b is ForumBodyPreparedListItemFragment ? b.body : b;
            expect(
              (body as ForumBodyPreparedParagraphFragment)
                  .lease
                  .content
                  .style
                  .indent,
              ForumBodyLength.zero,
            );
          }
        } finally {
          for (final b in bindings) {
            b.close();
          }
        }
      }
      expect(f.collectText(), first + last);
    },
  );

  testWidgets(
    'visible inline code tap resolves its actual source after preserved spaces',
    (tester) async {
      final f = _Fixture('<p>x<code>  ab</code>z</p>');
      f.drain();
      final bindings = f.prepare(0);
      int? source;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 180,
              height: f.height,
              child: ForumBodyTextPageSurface.prepared(
                snapshot: f.session.snapshot,
                pageIndex: 0,
                layoutId: 'code-pages',
                fragments: bindings,
                onSourceTap: (_, p) {
                  source = p.sourceRune;
                },
              ),
            ),
          ),
        ),
      );
      final binding = bindings.single as ForumBodyPreparedParagraphFragment;
      final box = binding.glyphBoxes(3, 4).single;
      final fragment = f.session.snapshot.single.fragments.single;
      await tester.tapAt(
        Offset(
          fragment.left + box.left + (box.right - box.left) * .25,
          fragment.top + (box.top + box.bottom) * .5,
        ),
      );
      expect(source, binding.projection.sourceAtUtf16(3).sourceRune);
      expect(source, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
    },
  );
}
