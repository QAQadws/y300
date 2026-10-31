import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

const _html =
    '<p>甲 &amp; e\u0301 👩🏽‍💻<br>乙<span hidden>隐藏</span></p>'
    '<div class="quote"><blockquote>引用</blockquote></div>'
    '<ruby>字<rt>じ</rt></ruby><img src="https://example.com/a.png">';

ForumBodyPreparationInput _input({
  String html = _html,
  String sourceId = 'synthetic:body',
  String conversionIdentity = 'original:v1',
  ForumBodyParseLimits limits = const ForumBodyParseLimits(),
}) => ForumBodyPreparationInput(
  html: html,
  sourceId: sourceId,
  conversionIdentity: conversionIdentity,
  limits: limits,
);

void main() {
  test(
    'real isolate preserves IR, source coordinates and provenance',
    () async {
      final executor = ForumBodyPreparationExecutor();
      addTearDown(executor.dispose);
      final input = _input();
      final expected = input.prepareSynchronously();
      final lease = executor.tryAcquire(input)!;
      final actual = (await lease.future)!;
      lease.release();
      expect(_projection(actual), _projection(expected));
      expect(() => actual.nodes.clear(), throwsUnsupportedError);
      expect(actual.nodesByPath.keys, expected.nodesByPath.keys);
    },
  );

  test(
    'pure input is sendable and parse failures retain typed limits',
    () async {
      final input = _input();
      final mainIsolate = Isolate.current.hashCode;
      final result = await Isolate.run(
        () => (Isolate.current.hashCode, input.prepareSynchronously().identity),
      );
      expect(result.$1, isNot(mainIsolate));
      expect(result.$2, input.prepareSynchronously().identity);
      final executor = ForumBodyPreparationExecutor();
      addTearDown(executor.dispose);
      final lease = executor.tryAcquire(
        _input(limits: const ForumBodyParseLimits(maxNodes: 1)),
      )!;
      await expectLater(
        lease.future,
        throwsA(
          isA<ForumBodyParseException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParseFailure.nodeLimit,
          ),
        ),
      );
      lease.release();
    },
  );

  test('identity includes actual conversion, source and admission limits', () {
    expect(_input().identity, _input().identity);
    for (final input in [
      _input(html: '<p>different</p>'),
      _input(sourceId: 'synthetic:other'),
      _input(conversionIdentity: 'traditional:v2'),
      _input(limits: const ForumBodyParseLimits(maxNodes: 8)),
      _input(limits: const ForumBodyParseLimits(maxDepth: 8)),
      _input(limits: const ForumBodyParseLimits(maxCodeUnits: 8)),
    ]) {
      expect(input.identity, isNot(_input().identity));
    }
    final executor = ForumBodyPreparationExecutor(codeUnitThreshold: 8);
    addTearDown(executor.dispose);
    expect(executor.usesBackground(_input(html: 'short')), isFalse);
    expect(executor.usesBackground(_input(html: '12345678')), isTrue);
  });

  test(
    'HTML and native facades share budget and native queued close',
    () async {
      final scheduler = ForumPreparationScheduler(maxQueued: 1);
      addTearDown(scheduler.dispose);
      final gate = Completer<void>();
      final html = ForumHtmlPreparationExecutor.withScheduler(
        scheduler: scheduler,
        worker: (input) async {
          await gate.future;
          return input.prepare();
        },
      );
      addTearDown(html.dispose);
      var nativeStarts = 0;
      final native = ForumBodyPreparationExecutor(
        scheduler: scheduler,
        worker: (input) async {
          nativeStarts++;
          return input.prepareSynchronously();
        },
      );
      final running = html.tryAcquire(
        ForumHtmlPreparationRequest(
          html: 'synthetic',
          preferences: ForumHtmlReaderPreferences.defaults(),
          theme: const ForumHtmlThemeContext(
            brightness: ForumHtmlBrightness.light,
            surface: Color(0xFFFFFFFF),
            foreground: Color(0xFF202020),
            link: Color(0xFF1565C0),
            quoteSurface: Color(0xFFF0F0F0),
            quoteForeground: Color(0xFF303030),
            codeSurface: Color(0xFFEDEDED),
            codeForeground: Color(0xFF202020),
          ),
          sourceId: 'synthetic',
          threadId: null,
          imageCacheOwnerId: null,
          preparer: const DefaultForumHtmlRenderPreparer(),
        ),
      )!;
      final queued = native.tryAcquire(_input())!;
      expect(native.tryAcquire(_input(sourceId: 'other')), isNull);
      expect(html.activeCount, 1);
      expect(native.queuedCodeUnits, _html.length);
      native.dispose();
      expect(await queued.future, isNull);
      expect(nativeStarts, 0);
      expect(html.queuedCount, 0);
      expect(html.activeCount, 1);
      expect(() => native.tryAcquire(_input()), throwsStateError);
      gate.complete();
      await running.future;
      running.release();
      queued.release();
    },
  );
}

Object _projection(ForumBodyDocument document) => [
  document.identity.cacheIdentity,
  document.sourceText,
  document.sourceMap.runeLength,
  document.sourceMap.graphemeLength,
  document.parsedNodeCount,
  document.uniqueStyleCount,
  for (final node in document.descendants)
    [
      node.path,
      node.source.runeStart,
      node.source.runeEnd,
      node.source.graphemeStart,
      node.source.graphemeEnd,
      if (node is ForumBodyText) node.text,
      if (node is ForumBodyElement)
        [
          node.kind,
          node.tag,
          node.attributes,
          for (final declaration in node.style.declarations)
            [declaration.property, declaration.value, declaration.important],
        ],
    ],
];
