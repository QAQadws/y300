import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_render_cache_key.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/models/thread_post_segmentation_config.dart';

void main() {
  group('ThreadPostBodyRenderSettings value equality', () {
    test('equal when all fields match', () {
      const a = ThreadPostBodyRenderSettings(
        fontSize: 18,
        lineHeight: 1.6,
        textTransformerKey: 'key',
      );
      const b = ThreadPostBodyRenderSettings(
        fontSize: 18,
        lineHeight: 1.6,
        textTransformerKey: 'key',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when one field differs', () {
      const base = ThreadPostBodyRenderSettings(fontSize: 16);
      const changed = ThreadPostBodyRenderSettings(fontSize: 20);
      expect(base, isNot(equals(changed)));
    });

    test('null and non-null fontSize are different', () {
      const withFont = ThreadPostBodyRenderSettings(fontSize: 16);
      const withoutFont = ThreadPostBodyRenderSettings();
      expect(withFont, isNot(equals(withoutFont)));
    });
  });

  group('ThreadPostBlockImageLayoutHint value equality', () {
    test('equal hints share same hashCode', () {
      const a = ThreadPostBlockImageLayoutHint(
        aspectRatio: 1.5,
        source: ThreadPostResourceLayoutHintSource.htmlAttribute,
        lockForCurrentBuild: true,
      );
      const b = ThreadPostBlockImageLayoutHint(
        aspectRatio: 1.5,
        source: ThreadPostResourceLayoutHintSource.htmlAttribute,
        lockForCurrentBuild: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differ on aspectRatio', () {
      const a = ThreadPostBlockImageLayoutHint(
        aspectRatio: 1.0,
        source: ThreadPostResourceLayoutHintSource.contentDefault,
        lockForCurrentBuild: false,
      );
      const b = ThreadPostBlockImageLayoutHint(
        aspectRatio: 1.5,
        source: ThreadPostResourceLayoutHintSource.contentDefault,
        lockForCurrentBuild: false,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('ThreadPostRenderCacheKey value equality', () {
    const defaultKey = ThreadPostRenderCacheKey(
      renderSettings: ThreadPostBodyRenderSettings.defaults,
      displayTransformerSignature: 'identity',
      resourceHintResolverSignature: '0.700000|false|false|noLookup',
      segmentation: ThreadPostSegmentationConfig.standard,
    );

    test('identical config → equal keys', () {
      const same = ThreadPostRenderCacheKey(
        renderSettings: ThreadPostBodyRenderSettings.defaults,
        displayTransformerSignature: 'identity',
        resourceHintResolverSignature: '0.700000|false|false|noLookup',
        segmentation: ThreadPostSegmentationConfig.standard,
      );
      expect(defaultKey, equals(same));
      expect(defaultKey.hashCode, same.hashCode);
    });

    test('changed renderSettings → unequal keys', () {
      final withFont = ThreadPostRenderCacheKey(
        renderSettings: ThreadPostBodyRenderSettings.defaults.copyWith(
          fontSize: 20,
        ),
        displayTransformerSignature: 'identity',
        resourceHintResolverSignature: '0.700000|false|false|noLookup',
        segmentation: ThreadPostSegmentationConfig.standard,
      );
      expect(defaultKey, isNot(equals(withFont)));
    });

    test('changed transformer signature → unequal keys', () {
      const withTransformer = ThreadPostRenderCacheKey(
        renderSettings: ThreadPostBodyRenderSettings.defaults,
        displayTransformerSignature: 'simp2trad',
        resourceHintResolverSignature: '0.700000|false|false|noLookup',
        segmentation: ThreadPostSegmentationConfig.standard,
      );
      expect(defaultKey, isNot(equals(withTransformer)));
    });

    test('changed segmentation → unequal keys', () {
      const withSmallSeg = ThreadPostRenderCacheKey(
        renderSettings: ThreadPostBodyRenderSettings.defaults,
        displayTransformerSignature: 'identity',
        resourceHintResolverSignature: '0.700000|false|false|noLookup',
        segmentation: ThreadPostSegmentationConfig(maxSegmentTextLength: 300),
      );
      expect(defaultKey, isNot(equals(withSmallSeg)));
    });
  });

  group('ThreadPostSegmentationConfig value equality', () {
    test('standard instances are equal', () {
      expect(
        ThreadPostSegmentationConfig.standard,
        equals(const ThreadPostSegmentationConfig()),
      );
    });

    test('differ on maxSegmentTextLength', () {
      expect(
        const ThreadPostSegmentationConfig(maxSegmentTextLength: 300),
        isNot(equals(ThreadPostSegmentationConfig.standard)),
      );
    });
  });
}
