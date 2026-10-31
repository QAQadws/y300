import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_anchor_binder.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

class _Source {
  _Source(this.html, {bool capture = true})
    : semantic =
          DiscuzNovelReaderDocumentParser(captureSourceProvenance: capture)
              .parse(
                episodeId: 'episode',
                rawHtml: html,
                fallbackParagraphs: const [],
              );
  final String html;
  final NovelReaderDocument semantic;
}

Future<NovelReaderNativeChapterPreparation> _resolve(
  NovelReaderNativePreparationCache cache,
  NovelReaderNativePreparationService service,
  _Source source, {
  NovelReaderPaginationCancellationToken? token,
  String sourceId = 'source',
  TextConverter converter = const IdentityTextConverter(),
}) => cache.resolve(
  service: service,
  episodeId: 'episode',
  sourceId: sourceId,
  rawHtml: source.html,
  semanticDocument: source.semantic,
  converter: converter,
  cancellation: token ?? NovelReaderPaginationCancellationToken(),
);

class _Service implements NovelReaderNativePreparationService {
  int calls = 0;
  @override
  Future<NovelReaderNativeChapterPreparation> prepare({
    required String episodeId,
    required String sourceId,
    required String rawHtml,
    required NovelReaderDocument semanticDocument,
    required NovelReaderPaginationCancellationToken cancellation,
    TextConverter converter = const IdentityTextConverter(),
  }) {
    calls++;
    return const DefaultNovelReaderNativePreparationService().prepare(
      episodeId: episodeId,
      sourceId: sourceId,
      rawHtml: rawHtml,
      semanticDocument: semanticDocument,
      cancellation: cancellation,
      converter: converter,
    );
  }
}

class _Gated implements NovelReaderNativePreparationService {
  final pending = <Completer<NovelReaderNativeChapterPreparation>>[];
  final tokens = <NovelReaderPaginationCancellationToken>[];
  @override
  Future<NovelReaderNativeChapterPreparation> prepare({
    required String episodeId,
    required String sourceId,
    required String rawHtml,
    required NovelReaderDocument semanticDocument,
    required NovelReaderPaginationCancellationToken cancellation,
    TextConverter converter = const IdentityTextConverter(),
  }) {
    final work = Completer<NovelReaderNativeChapterPreparation>();
    pending.add(work);
    tokens.add(cancellation);
    return work.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('same source coalesces and reuses pure data independently of layout/typography', () async {
    final cache = NovelReaderNativePreparationCache();
    addTearDown(cache.dispose);
    final source = _Source('<p>same source</p>');
    final service = _Service();
    final a = _resolve(cache, service, source);
    final b = _resolve(cache, service, source);
    final results = await Future.wait([a, b]);
    expect(results.first, same(results.last));
    expect(await _resolve(cache, service, source), same(results.first));
    expect(service.calls, 1);
    expect(cache.length, 1);
    expect(cache.inFlightCount, 0);
    expect(cache.estimatedRetainedBytes, greaterThan(0));
  });

  test(
    'one cancelled layout cannot cancel another caller of the same source',
    () async {
      final cache = NovelReaderNativePreparationCache();
      addTearDown(cache.dispose);
      final source = _Source('<p>shared</p>');
      final service = _Gated();
      final token = NovelReaderPaginationCancellationToken();
      final first = _resolve(cache, service, source, token: token);
      final checked = expectLater(
        first,
        throwsA(isA<NovelReaderPaginationException>()),
      );
      final second = _resolve(cache, service, source);
      expect(service.pending, hasLength(1));
      token.cancel();
      await checked;
      expect(service.tokens.single.isCancelled, isFalse);
      final expected = await _resolve(
        NovelReaderNativePreparationCache(maxEstimatedBytes: 0),
        _Service(),
        source,
      );
      service.pending.single.complete(expected);
      expect(await second, same(expected));
      expect(await _resolve(cache, service, source), same(expected));
    },
  );

  test('semantic identity, exact input, source and service prevent unsafe warm hits', () async {
    final cache = NovelReaderNativePreparationCache();
    addTearDown(cache.dispose);
    final service = _Service();
    final source = _Source('<p>same</p>');
    await _resolve(cache, service, source);
    await expectLater(
      _resolve(cache, service, _Source('<p>same</p>', capture: false)),
      throwsA(isA<NovelReaderNativeAnchorBindingException>()),
    );
    await _resolve(cache, service, source, sourceId: 'another-source');
    final otherService = _Service();
    await _resolve(cache, otherService, source);
    expect(service.calls, 3);
    expect(otherService.calls, 1);
    await expectLater(
      cache.resolve(
        service: service,
        episodeId: 'episode',
        sourceId: 'source',
        rawHtml: '<div>same</div>',
        semanticDocument: source.semantic,
        cancellation: NovelReaderPaginationCancellationToken(),
      ),
      throwsA(isA<NovelReaderNativeAnchorBindingException>()),
    );
  });

  test('LRU and estimated-byte rejection bound retention without rejecting useful data', () async {
    final cache = NovelReaderNativePreparationCache(maxEntries: 2);
    addTearDown(cache.dispose);
    final service = _Service();
    final a = _Source('<p>a</p>'),
        b = _Source('<p>b</p>'),
        c = _Source('<p>c</p>');
    await _resolve(cache, service, a);
    await _resolve(cache, service, b);
    await _resolve(cache, service, a);
    await _resolve(cache, service, c);
    expect(cache.length, 2);
    await _resolve(cache, service, b);
    expect(service.calls, 4);
    final uncached = NovelReaderNativePreparationCache(maxEstimatedBytes: 0);
    addTearDown(uncached.dispose);
    expect(
      await _resolve(uncached, service, a),
      isA<NovelReaderNativePreparedChapter>(),
    );
    expect(uncached.length, 0);
    expect(uncached.estimatedRetainedBytes, 0);
  });

  test('clear detaches an old flight and cannot replace or erase the newer same-key work', () async {
    final cache = NovelReaderNativePreparationCache();
    addTearDown(cache.dispose);
    final service = _Gated();
    final source = _Source('<p>value</p>');
    final old = _resolve(cache, service, source);
    cache.clear();
    final next = _resolve(cache, service, source);
    final value = await _resolve(
      NovelReaderNativePreparationCache(maxEstimatedBytes: 0),
      _Service(),
      source,
    ) as NovelReaderNativePreparedChapter;
    final newer = NovelReaderNativePreparedChapter(
      episodeId: value.episodeId,
      convertedTextNodeCount: 7,
      document: value.document,
      anchors: value.anchors,
    );
    service.pending[1].complete(newer);
    expect(await next, same(newer));
    service.pending[0].complete(value);
    expect(await old, same(value));
    expect(await _resolve(cache, service, source), same(newer));
    expect(cache.inFlightCount, 0);
  });

  test('active-flight cap includes detached work and owner close observes late failures', () async {
    final cache = NovelReaderNativePreparationCache(maxInFlight: 1);
    final service = _Gated();
    final first = _resolve(cache, service, _Source('<p>a</p>'));
    final checked = expectLater(
      first,
      throwsA(isA<NovelReaderPaginationException>()),
    );
    cache.clear();
    await expectLater(
      _resolve(cache, service, _Source('<p>b</p>')),
      throwsA(isA<NovelReaderNativePreparationBudgetException>()),
    );
    cache.dispose();
    await checked;
    expect(service.tokens.single.isCancelled, isTrue);
    expect(cache.inFlightCount, 0);
    expect(cache.estimatedRetainedBytes, 0);
    service.pending.single.completeError(StateError('late source failure'));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      _resolve(cache, service, _Source('<p>c</p>')),
      throwsStateError,
    );
  });
}
