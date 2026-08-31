import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';

void main() {
  group('ThreadPostResourceLayoutHintResolver dimension hydration', () {
    const imageNoDimension = RichImageBlock(
      url: 'https://bbs.yamibo.com/data/attachment/forum/a.jpg',
      rawUrl: 'data/attachment/forum/a.jpg',
      index: 0,
    );
    const imageWithHtml = RichImageBlock(
      url: 'https://bbs.yamibo.com/data/attachment/forum/b.jpg',
      rawUrl: 'data/attachment/forum/b.jpg',
      index: 1,
      originalWidth: 800,
      originalHeight: 400,
    );

    test('falls back to lookup dimensions and marks them locked & trusted', () {
      final lookup = _FakeDimensionLookup(
        signature: 'fixture-1',
        blockDimensions: <String, ThreadPostResourceDimension>{
          ThreadPostResourceLayoutHints.blockImageKey(imageNoDimension):
              const ThreadPostResourceDimension(width: 1000, height: 500),
        },
      );
      const resolver = ThreadPostResourceLayoutHintResolver(
        lockTrustedDimensions: true,
      );
      final hydrated = resolver.copyWithLookup(lookup);
      final hints = hydrated.resolve(
        const RichDocument(blocks: <RichBlock>[imageNoDimension]),
      );

      final hint = hints.blockImage(imageNoDimension);
      expect(hint, isNotNull);
      expect(hint!.aspectRatio, closeTo(2.0, 0.0001));
      expect(hint.source, ThreadPostResourceLayoutHintSource.cachedDimension);
      expect(hint.lockForCurrentBuild, isTrue);
    });

    test('prefers HTML dimensions over lookup', () {
      final lookup = _FakeDimensionLookup(
        signature: 'fixture-2',
        blockDimensions: <String, ThreadPostResourceDimension>{
          ThreadPostResourceLayoutHints.blockImageKey(imageWithHtml):
              const ThreadPostResourceDimension(width: 100, height: 900),
        },
      );
      const resolver = ThreadPostResourceLayoutHintResolver(
        lockTrustedDimensions: true,
      );
      final hints = resolver
          .copyWithLookup(lookup)
          .resolve(const RichDocument(blocks: <RichBlock>[imageWithHtml]));

      final hint = hints.blockImage(imageWithHtml)!;
      expect(hint.aspectRatio, closeTo(2.0, 0.0001));
      expect(hint.source, ThreadPostResourceLayoutHintSource.htmlAttribute);
    });

    test(
      'without lookup keeps unlocked content default for unknown images',
      () {
        const resolver = ThreadPostResourceLayoutHintResolver(
          lockTrustedDimensions: true,
        );
        final hints = resolver.resolve(
          const RichDocument(blocks: <RichBlock>[imageNoDimension]),
        );
        final hint = hints.blockImage(imageNoDimension)!;
        expect(hint.source, ThreadPostResourceLayoutHintSource.contentDefault);
        expect(hint.lockForCurrentBuild, isFalse);
      },
    );

    test('signature reflects lookup signature so plan cache invalidates', () {
      const base = ThreadPostResourceLayoutHintResolver();
      final withLookupA = base.copyWithLookup(
        _FakeDimensionLookup(signature: 'rev:1'),
      );
      final withLookupB = base.copyWithLookup(
        _FakeDimensionLookup(signature: 'rev:2'),
      );
      expect(base.signature, isNot(withLookupA.signature));
      expect(withLookupA.signature, isNot(withLookupB.signature));
    });
  });
}

/// 便于在测试里复用一个 resolver 但替换 lookup。
extension on ThreadPostResourceLayoutHintResolver {
  ThreadPostResourceLayoutHintResolver copyWithLookup(
    ThreadPostImageDimensionLookup lookup,
  ) {
    return ThreadPostResourceLayoutHintResolver(
      defaultBlockImageAspectRatio: defaultBlockImageAspectRatio,
      lockForCurrentBuild: lockForCurrentBuild,
      lockTrustedDimensions: lockTrustedDimensions,
      dimensionLookup: lookup,
    );
  }
}

class _FakeDimensionLookup implements ThreadPostImageDimensionLookup {
  _FakeDimensionLookup({
    required this.signature,
    this.blockDimensions = const <String, ThreadPostResourceDimension>{},
  });

  @override
  final String signature;
  final Map<String, ThreadPostResourceDimension> blockDimensions;

  @override
  ThreadPostResourceDimension? blockImageDimension(RichImageBlock image) {
    return blockDimensions[ThreadPostResourceLayoutHints.blockImageKey(image)];
  }

  @override
  ThreadPostResourceDimension? inlineImageDimension(RichInlineImage image) {
    return null;
  }
}
