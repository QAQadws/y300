import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_anchor_binder.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

NovelReaderDocument _semantic(
  String html, {
  bool capture = true,
  List<String> fallback = const [],
  String? conversion = 'none',
}) {
  final value = DiscuzNovelReaderDocumentParser(
    captureSourceProvenance: capture,
  ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: fallback);
  return NovelReaderDocument(
    episodeId: value.episodeId,
    rawHtmlHash: value.rawHtmlHash,
    body: value.body,
    plainText: value.plainText,
    wordCount: value.wordCount,
    textConversionIdentity: conversion,
    sourceProvenance: value.sourceProvenance,
    storedParagraphSource: value.storedParagraphSource,
  );
}

Future<NovelReaderNativeChapterPreparation> _prepare(
  String html,
  NovelReaderDocument semantic, {
  NovelReaderNativePreparationService service =
      const DefaultNovelReaderNativePreparationService(),
  NovelReaderPaginationCancellationToken? cancellation,
}) => service.prepare(
  episodeId: 'episode',
  sourceId: 'source',
  rawHtml: html,
  semanticDocument: semantic,
  cancellation: cancellation ?? NovelReaderPaginationCancellationToken(),
);

Matcher _bindingFailure(NovelReaderNativeAnchorBindingFailure failure) =>
    isA<NovelReaderNativeAnchorBindingException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production short and real-worker preparation reuse semantic conversion and exact origins', () async {
    const channel = MethodChannel('flutter_open_chinese_convert');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return ((call.arguments as List<Object?>).first as String).replaceAll(
        '臺',
        '台',
      );
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final converter = resolveTextConverter(TextConversionMode.toSimplified);
    for (final count in [3, 13000]) {
      final html = ' \n<p title="臺属性">${List.filled(count, '臺').join()}</p>\n ';
      final semantic = await container
          .read(novelReaderDocumentBuildServiceProvider)
          .build(
            NovelReaderDocumentBuildRequest(
              episodeId: 'episode',
              rawHtml: html,
              fallbackParagraphs: const [],
            ),
            converter: converter,
          );
      expect(semantic.sourceProvenance, isNotNull);
      expect(semantic.plainText, List.filled(count, '台').join());
      final callsBefore = calls.length;
      final prepared =
          await container
                  .read(novelReaderNativePreparationServiceProvider)
                  .prepare(
                    episodeId: 'episode',
                    sourceId: 'source',
                    rawHtml: html,
                    semanticDocument: semantic,
                    converter: converter,
                    cancellation: NovelReaderPaginationCancellationToken(),
                  )
              as NovelReaderNativePreparedChapter;
      expect(
        calls.length,
        callsBefore,
        reason: 'Reuse the shared actual HTML conversion',
      );
      expect(prepared.identity.conversionIdentity, 'toSimplified');
      expect(prepared.identity.inputHash, semantic.sourceProvenance!.inputHash);
      expect(prepared.anchors.identity, prepared.identity);
      expect(
        prepared.anchors.segments.single.projection.baseAnchor.nodeId,
        'node-0',
      );
      expect(prepared.anchors.sourceRuneLength, count);
      expect(prepared.convertedTextNodeCount, 1);
    }
  });

  test(
    'raw source binding preserves literal BR and recorded node boundaries',
    () async {
      const html = '<p>甲<a href="/thread-123-1-1.html">乙<br>丙</a>丁</p>';
      final semantic = _semantic(html);
      final prepared =
          await _prepare(html, semantic) as NovelReaderNativePreparedChapter;
      expect(prepared.identity.inputHash, semantic.sourceProvenance!.inputHash);
      expect(prepared.anchors.segments, isNotEmpty);
      expect(prepared.document.nodeAtPath('0/1'), isNotNull);
      expect(prepared.document.nodeAtPath('0/1/1'), isNotNull);
      expect(prepared.convertedTextNodeCount, 0);
    },
  );

  test('only truly absent input and empty semantics produce the explicit empty outcome', () async {
    const html = ' \n\t ';
    final empty = await _prepare(html, _semantic(html));
    expect(empty, isA<NovelReaderNativeEmptyChapter>());
    expect(empty.episodeId, 'episode');
    expect(empty.identity.conversionIdentity, 'none');
  });

  for (final html in ['   ', '<script>irrelevant</script>']) {
    test(
      'stored paragraphs use literal text with exact, distinct anchors ($html)',
      () async {
        const text = '🙂 <img src=x> & 字\n再一行';
        final semantic = _semantic(html, fallback: [text, ' ', text]);
        expect(semantic.sourceProvenance, isNull);
        final prepared =
            await _prepare(html, semantic) as NovelReaderNativePreparedChapter;
        expect(prepared.document.imageElements, isEmpty);
        expect(prepared.document.sourceMap.runeLength, text.runes.length * 2);
        expect(prepared.anchors.unmappedPaths, isEmpty);
        for (var index = 0; index < 2; index++) {
          final node =
              prepared.document.nodeAtPath('$index/0') as ForumBodyText;
          final segment = prepared.anchors.segments[index];
          expect(node.text, text);
          expect(segment.sourceStart, node.source.runeStart);
          expect(segment.sourceEnd, node.source.runeEnd);
          expect(segment.projection.baseAnchor.nodeId, 'node-$index');
          expect(
            segment.projection.baseAnchor.textIdentity,
            NovelReaderAnchorFormat.textIdentity(text),
          );
          final anchor = prepared.anchors.anchorAtSourceRune(
            segment.sourceStart + 1,
            affinity: HtmlProjectionAffinity.downstream,
          )!;
          expect((anchor.nodeId, anchor.textOffset), ('node-$index', 1));
        }
        await expectLater(
          _prepare('<p>new HTML</p>', semantic),
          throwsA(
            _bindingFailure(NovelReaderNativeAnchorBindingFailure.identity),
          ),
        );
      },
    );
  }

  test(
    'native stored text uses the semantic conversion exactly once',
    () async {
      const channel = MethodChannel('flutter_open_chinese_convert');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        return ((call.arguments as List<Object?>).first as String).replaceAll(
          '臺',
          '台',
        );
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final converter = resolveTextConverter(TextConversionMode.toSimplified);
      final semantic = await container
          .read(novelReaderDocumentBuildServiceProvider)
          .build(
            const NovelReaderDocumentBuildRequest(
              episodeId: 'episode',
              rawHtml: '',
              fallbackParagraphs: ['臺 & 字'],
            ),
            converter: converter,
          );
      final before = calls;
      expect(before, greaterThan(0));
      final prepared =
          await container
                  .read(novelReaderNativePreparationServiceProvider)
                  .prepare(
                    episodeId: 'episode',
                    sourceId: 'source',
                    rawHtml: '',
                    semanticDocument: semantic,
                    cancellation: NovelReaderPaginationCancellationToken(),
                    converter: converter,
                  )
              as NovelReaderNativePreparedChapter;
      expect(calls, before);
      expect(prepared.identity.conversionIdentity, 'toSimplified');
      expect(
        (prepared.document.nodeAtPath('0/0') as ForumBodyText).text,
        '台 & 字',
      );
      expect(
        prepared.anchors.segments.single.projection.baseAnchor.textIdentity,
        NovelReaderAnchorFormat.textIdentity('台 & 字'),
      );
    },
  );

  test(
    'missing provenance and different exact input fail without text matching',
    () async {
      const html = '<p>same</p>';
      await expectLater(
        _prepare(html, _semantic(html, capture: false)),
        throwsA(
          _bindingFailure(NovelReaderNativeAnchorBindingFailure.provenance),
        ),
      );
      await expectLater(
        _prepare('<div>same</div>', _semantic(html)),
        throwsA(
          _bindingFailure(NovelReaderNativeAnchorBindingFailure.identity),
        ),
      );
    },
  );

  test(
    'unknown/preview conversion and wrong episode never start preparation',
    () async {
      final executor = _GatedExecutor();
      final service = DefaultNovelReaderNativePreparationService(
        executor: executor,
      );
      for (final conversion in [null, 'toTraditional']) {
        await expectLater(
          _prepare(
            '<p>a</p>',
            _semantic('<p>a</p>', conversion: conversion),
            service: service,
          ),
          throwsA(
            _bindingFailure(NovelReaderNativeAnchorBindingFailure.conversion),
          ),
        );
      }
      await expectLater(
        service.prepare(
          episodeId: 'different',
          sourceId: 'source',
          rawHtml: '<p>a</p>',
          semanticDocument: _semantic('<p>a</p>'),
          cancellation: NovelReaderPaginationCancellationToken(),
        ),
        throwsA(
          _bindingFailure(NovelReaderNativeAnchorBindingFailure.identity),
        ),
      );
      expect(executor.requests, isEmpty);
    },
  );

  test(
    'cancellation retires a pending worker result and observes late failure',
    () async {
      final executor = _GatedExecutor();
      final cancellation = NovelReaderPaginationCancellationToken();
      final work = _prepare(
        '<p>a</p>',
        _semantic('<p>a</p>'),
        cancellation: cancellation,
        service: DefaultNovelReaderNativePreparationService(executor: executor),
      );
      final checked = expectLater(
        work,
        throwsA(isA<NovelReaderPaginationException>()),
      );
      expect(executor.requests, hasLength(1));
      cancellation.cancel();
      await checked;
      executor.completed.completeError(StateError('late worker failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'cancellation during Host conversion does not dispatch a worker',
    () async {
      final conversion = _GatedConversion();
      final executor = _GatedExecutor();
      final cancellation = NovelReaderPaginationCancellationToken();
      final work =
          DefaultNovelReaderNativePreparationService(
            conversionService: conversion,
            executor: executor,
          ).prepare(
            episodeId: 'episode',
            sourceId: 'source',
            rawHtml: '<p>a</p>',
            semanticDocument: _semantic('<p>a</p>', conversion: 'toSimplified'),
            converter: resolveTextConverter(TextConversionMode.toSimplified),
            cancellation: cancellation,
          );
      final checked = expectLater(
        work,
        throwsA(isA<NovelReaderPaginationException>()),
      );
      cancellation.cancel();
      await checked;
      conversion.completed.completeError(StateError('late conversion failure'));
      await Future<void>.delayed(Duration.zero);
      expect(executor.requests, isEmpty);
    },
  );
}

final class _GatedExecutor implements NovelReaderNativeChapterBuildExecutor {
  final requests = <NovelReaderNativeChapterBuildRequest>[];
  final completed = Completer<NovelReaderNativeChapterPreparation>();
  @override
  Future<NovelReaderNativeChapterPreparation> build(
    NovelReaderNativeChapterBuildRequest request,
  ) {
    requests.add(request);
    return completed.future;
  }
}

final class _GatedConversion extends HtmlTextNodeConversionService {
  final completed = Completer<List<HtmlTextNodeConversionResult>>();
  @override
  Future<List<HtmlTextNodeConversionResult>> convertAll({
    required List<String> htmlFragments,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  }) => completed.future;
}
