import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_preference_impact_analyzer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_shared_preferences_bridge.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

void main() {
  group('AdaptiveNovelReaderDocumentBuildService conversion', () {
    test('applies converter to html and fallback paragraphs', () async {
      final service = AdaptiveNovelReaderDocumentBuildService(
        parser: const DiscuzNovelReaderDocumentParser(),
        executor: _ThrowingExecutor(),
      );

      final document = await service.build(
        const NovelReaderDocumentBuildRequest(
          episodeId: 'ep1',
          rawHtml: '<p>abc</p>',
          fallbackParagraphs: <String>['abc'],
        ),
        converter: _UppercaseConverter(),
      );

      expect((document.blocks.first as RichTextBlock).novelPlainText, 'ABC');
    });

    test('identity converter leaves content unchanged', () async {
      final service = AdaptiveNovelReaderDocumentBuildService(
        parser: const DiscuzNovelReaderDocumentParser(),
        executor: _ThrowingExecutor(),
      );

      final document = await service.build(
        const NovelReaderDocumentBuildRequest(
          episodeId: 'ep1',
          rawHtml: '<p>第一段</p>',
          fallbackParagraphs: <String>['第一段'],
        ),
      );

      expect((document.blocks.first as RichTextBlock).novelPlainText, '第一段');
    });
  });

  group('NovelReaderPreferences conversionMode', () {
    test('defaults to none', () {
      expect(
        NovelReaderPreferences.defaults().conversionMode,
        NovelReaderConversionMode.none,
      );
    });

    test('participates in equality', () {
      final base = NovelReaderPreferences.defaults();
      final changed = base.copyWith(
        conversionMode: NovelReaderConversionMode.toTraditional,
      );
      expect(base, isNot(equals(changed)));
    });

    test('copyWith preserves conversionMode when not specified', () {
      final base = NovelReaderPreferences.defaults().copyWith(
        conversionMode: NovelReaderConversionMode.toSimplified,
      );
      final next = base.copyWith(fontSize: 22);
      expect(next.conversionMode, NovelReaderConversionMode.toSimplified);
    });
  });

  group('NovelReaderConversionModeCodec', () {
    test('round-trips all values', () {
      for (final mode in NovelReaderConversionMode.values) {
        expect(
          NovelReaderConversionModeCodec.fromStorage(mode.storageValue),
          mode,
        );
      }
    });

    test('unknown value falls back to none', () {
      expect(
        NovelReaderConversionModeCodec.fromStorage('garbage'),
        NovelReaderConversionMode.none,
      );
      expect(
        NovelReaderConversionModeCodec.fromStorage(null),
        NovelReaderConversionMode.none,
      );
    });
  });

  group('NovelReaderPreferencesSharedBridge', () {
    test('maps conversion mode to shared enum', () {
      final prefs = NovelReaderPreferences.defaults().copyWith(
        conversionMode: NovelReaderConversionMode.toTraditional,
      );
      expect(prefs.sharedConversionMode, TextConversionMode.toTraditional);
    });

    test('maps typography scales from absolute fields', () {
      final prefs = NovelReaderPreferences.defaults().copyWith(
        fontSize: 36,
        lineHeight: 3.0,
        paragraphSpacing: 14,
      );
      final typography = prefs.sharedTypography;
      expect(typography.fontScale, 2.0);
      expect(typography.lineHeightScale, 2.0);
      expect(typography.paragraphSpacing, 14);
    });
  });

  group('NovelReaderPreferenceImpactAnalyzer conversion', () {
    const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();

    test('conversion mode change flags contentRebuild', () {
      final previous = NovelReaderPreferences.defaults();
      final next = previous.copyWith(
        conversionMode: NovelReaderConversionMode.toSimplified,
      );
      final diff = analyzer.compare(previous, next);
      expect(
        diff.impacts,
        contains(NovelReaderPreferenceImpact.contentRebuild),
      );
    });

    test('font size change does not flag contentRebuild', () {
      final previous = NovelReaderPreferences.defaults();
      final next = previous.copyWith(fontSize: 22);
      final diff = analyzer.compare(previous, next);
      expect(
        diff.impacts,
        isNot(contains(NovelReaderPreferenceImpact.contentRebuild)),
      );
    });
  });
}

class _UppercaseConverter implements TextConverter {
  @override
  String get id => 'test:uppercase';

  @override
  TextConversionMode get mode => TextConversionMode.toTraditional;

  @override
  Future<String> convertHtml(String html) async => html.toUpperCase();
}

class _ThrowingExecutor implements NovelReaderDocumentBuildExecutor {
  @override
  Future<NovelReaderDocument> buildInBackground(
    NovelReaderDocumentBuildRequest request,
  ) async {
    throw StateError('should not run in background for small requests');
  }
}
