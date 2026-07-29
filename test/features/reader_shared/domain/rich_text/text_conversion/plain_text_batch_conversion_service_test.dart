import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

void main() {
  group('DefaultPlainTextBatchConversionService', () {
    test(
      'keeps empty, non-Han and none-mode values without conversion',
      () async {
        final converter = _RecordingConverter();
        final service = DefaultPlainTextBatchConversionService();

        final result = await service.convertAll(
          sources: ['', 'hello', '，。！？', '漢字'],
          converter: converter,
        );

        expect(result, ['', 'hello', '，。！？', '漢字T']);
        expect(converter.callCount, 1);

        final identity = _RecordingConverter(mode: TextConversionMode.none);
        final identityResult = await service.convertAll(
          sources: ['漢字'],
          converter: identity,
        );
        expect(identityResult, ['漢字']);
        expect(identity.callCount, 0);
      },
    );

    test('preserves order and restores duplicate values', () async {
      final converter = _RecordingConverter();
      final service = DefaultPlainTextBatchConversionService();

      final result = await service.convertAll(
        sources: ['第一', '第二', '第一'],
        converter: converter,
      );

      expect(result, ['第一T', '第二T', '第一T']);
      expect(converter.callCount, 1);
      expect(
        converter.lastInput,
        contains(DefaultPlainTextBatchConversionService.delimiter),
      );
    });

    test(
      'uses individual conversion when a source contains the delimiter',
      () async {
        final converter = _RecordingConverter();
        final service = DefaultPlainTextBatchConversionService();
        final sourceWithDelimiter =
            '前${DefaultPlainTextBatchConversionService.delimiter}后';

        final result = await service.convertAll(
          sources: [sourceWithDelimiter, '普通'],
          converter: converter,
        );

        expect(result, [sourceWithDelimiter, '普通T']);
        expect(converter.callCount, 2);
        expect(
          converter.lastInputs,
          isNot(
            contains('普通${DefaultPlainTextBatchConversionService.delimiter}'),
          ),
        );
      },
    );

    test(
      'falls back to individual conversion when batch splitting is invalid',
      () async {
        final converter = _MalformedBatchConverter();
        final service = DefaultPlainTextBatchConversionService();

        final result = await service.convertAll(
          sources: ['正文', '尾巴'],
          converter: converter,
        );

        expect(result, ['正文T', '尾巴T']);
        expect(converter.callCount, 3);
      },
    );

    test('propagates converter failures', () async {
      final service = DefaultPlainTextBatchConversionService();

      await expectLater(
        service.convertAll(sources: ['正文'], converter: _ThrowingConverter()),
        throwsA(isA<StateError>()),
      );
    });

    test('isolates cache entries by converter id', () async {
      final service = DefaultPlainTextBatchConversionService();
      final traditional = _RecordingConverter(id: 'fake:s2t');
      final simplified = _RecordingConverter(id: 'fake:t2s', suffix: 'S');

      expect(
        await service.convertAll(sources: ['漢字'], converter: traditional),
        ['漢字T'],
      );
      expect(await service.convertAll(sources: ['漢字'], converter: simplified), [
        '漢字S',
      ]);
      expect(traditional.callCount, 1);
      expect(simplified.callCount, 1);
    });

    test('evicts least recently used entries', () async {
      final service = DefaultPlainTextBatchConversionService(
        maxCacheEntries: 1,
      );
      final converter = _RecordingConverter();

      await service.convertAll(sources: ['第一'], converter: converter);
      await service.convertAll(sources: ['第二'], converter: converter);
      await service.convertAll(sources: ['第一'], converter: converter);

      expect(converter.callCount, 3);
    });

    test('does not cache a batch over the code unit budget', () async {
      final service = DefaultPlainTextBatchConversionService(
        maxCacheCodeUnits: 1,
      );
      final converter = _RecordingConverter();

      await service.convertAll(sources: ['第一'], converter: converter);
      await service.convertAll(sources: ['第一'], converter: converter);

      expect(converter.callCount, 2);
    });

    test(
      'reports operation-scoped metrics without replacing global metrics',
      () async {
        final globalMetrics = <PlainTextBatchConversionMetrics>[];
        final operationMetrics = <PlainTextBatchConversionMetrics>[];
        final service = DefaultPlainTextBatchConversionService(
          metricsListener: globalMetrics.add,
        );
        final converter = _RecordingConverter();

        await service.convertAllObserved(
          sources: const <String>['漢字'],
          converter: converter,
          metricsListener: operationMetrics.add,
        );
        await service.convertAllObserved(
          sources: const <String>['漢字'],
          converter: converter,
          metricsListener: operationMetrics.add,
        );

        expect(globalMetrics, hasLength(2));
        expect(operationMetrics, hasLength(2));
        expect(operationMetrics.first.cacheHit, isFalse);
        expect(operationMetrics.last.cacheHit, isTrue);
        expect(operationMetrics.last.sourceCount, 1);
        expect(operationMetrics.last.failureType, isNull);
      },
    );
  });
}

class _RecordingConverter implements TextConverter {
  _RecordingConverter({
    this.id = 'fake:recording',
    this.suffix = 'T',
    this.mode = TextConversionMode.toTraditional,
  });

  @override
  final String id;

  final String suffix;
  @override
  final TextConversionMode mode;
  int callCount = 0;
  String lastInput = '';
  final List<String> lastInputs = [];

  @override
  Future<String> convertHtml(String html) async {
    callCount += 1;
    lastInput = html;
    lastInputs.add(html);
    return html
        .replaceAll('漢字', '漢字$suffix')
        .replaceAll('正文', '正文$suffix')
        .replaceAll('第一', '第一$suffix')
        .replaceAll('第二', '第二$suffix')
        .replaceAll('尾巴', '尾巴$suffix')
        .replaceAll('普通', '普通$suffix');
  }
}

class _MalformedBatchConverter extends _RecordingConverter {
  @override
  Future<String> convertHtml(String html) async {
    callCount += 1;
    lastInput = html;
    lastInputs.add(html);
    if (html.contains(DefaultPlainTextBatchConversionService.delimiter)) {
      return 'malformed';
    }
    callCount -= 1;
    return super.convertHtml(html);
  }
}

class _ThrowingConverter implements TextConverter {
  @override
  String get id => 'fake:throwing';

  @override
  TextConversionMode get mode => TextConversionMode.toTraditional;

  @override
  Future<String> convertHtml(String html) async {
    throw StateError('conversion failed');
  }
}
