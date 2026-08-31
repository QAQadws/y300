import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/opencc_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';

void main() {
  group('IdentityTextConverter', () {
    const converter = IdentityTextConverter();

    test('id is conv:none', () {
      expect(converter.id, 'conv:none');
    });

    test('mode is none', () {
      expect(converter.mode, TextConversionMode.none);
    });

    test('convertHtml returns input unchanged', () async {
      const html = '<p>你好世界</p>';
      expect(await converter.convertHtml(html), html);
    });

    test('convertHtml handles empty string', () async {
      expect(await converter.convertHtml(''), '');
    });
  });

  group('OpenccTextConverter', () {
    test('toTraditional has s2t in id', () {
      const converter = OpenccTextConverter(
        mode: TextConversionMode.toTraditional,
      );
      expect(converter.id, contains('s2t'));
      expect(converter.mode, TextConversionMode.toTraditional);
    });

    test('toSimplified has t2s in id', () {
      const converter = OpenccTextConverter(
        mode: TextConversionMode.toSimplified,
      );
      expect(converter.id, contains('t2s'));
      expect(converter.mode, TextConversionMode.toSimplified);
    });

    test('ids differ between directions', () {
      const s2t = OpenccTextConverter(mode: TextConversionMode.toTraditional);
      const t2s = OpenccTextConverter(mode: TextConversionMode.toSimplified);
      expect(s2t.id, isNot(t2s.id));
    });
  });

  group('resolveTextConverter', () {
    test('none resolves to IdentityTextConverter', () {
      final converter = resolveTextConverter(TextConversionMode.none);
      expect(converter, isA<IdentityTextConverter>());
    });

    test('toTraditional resolves to OpenccTextConverter s2t', () {
      final converter = resolveTextConverter(TextConversionMode.toTraditional);
      expect(converter, isA<OpenccTextConverter>());
      expect(converter.id, contains('s2t'));
    });

    test('toSimplified resolves to OpenccTextConverter t2s', () {
      final converter = resolveTextConverter(TextConversionMode.toSimplified);
      expect(converter, isA<OpenccTextConverter>());
      expect(converter.id, contains('t2s'));
    });
  });

  group('ThreadPostBodyRenderPlanner converterId', () {
    const document = RichDocument(
      blocks: <RichBlock>[
        RichTextBlock(runs: <RichRun>[RichRun(text: '正文')]),
      ],
    );
    const planner = ThreadPostBodyRenderPlanner();
    const defaultSettings = ThreadPostBodyRenderSettings.defaults;

    test('default plan has identity converterId', () {
      final plan = planner.planDocument(document);
      expect(plan.renderKey.converterId, 'conv:none');
    });

    test('converterId participates in cache key equality', () {
      final planDefault = planner.planDocument(document);
      final planConverted = planner.planDocument(
        document,
        converterId: 'opencc:0.9:s2t',
      );
      expect(planDefault.renderKey, isNot(planConverted.renderKey));
    });

    test('same converterId produces equal cache keys', () {
      final planA = planner.planDocument(
        document,
        renderSettings: defaultSettings,
        converterId: 'opencc:0.9:s2t',
      );
      final planB = planner.planDocument(
        document,
        renderSettings: defaultSettings,
        converterId: 'opencc:0.9:s2t',
      );
      expect(planA.renderKey, equals(planB.renderKey));
    });
  });
}
