import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_pair_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(() {
    cache = ForumBodyParagraphCache(maxEntries: 8, maxEstimatedBytes: 1 << 20);
  });
  tearDown(() {
    cache.close();
  });

  test(
    'cold and partial cached pair misses build nothing and release partial aliases',
    () {
      final input = rubyPairInput();
      expect(
        ForumBodyRubyGroupLayout.tryCreateCached(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
        ),
        isNull,
      );
      expect(cache.layoutBuildCount, 0);
      final external = cache.acquire(content: input.base, width: 100);
      expect(
        ForumBodyRubyGroupLayout.tryCreateCached(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
        ),
        isNull,
      );
      expect(cache.layoutBuildCount, 1);
      expect(cache.activeLeases, 1);
      expect(external.isActive, isTrue);
      external.release();
      cache.clearUnpinned();
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'cached pair uses identical geometry and current source without another build',
    () {
      final input = rubyPairInput(base: '👨‍👩‍👧‍👦', annotation: 'かな');
      final original = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 2,
      );
      final cached = ForumBodyRubyGroupLayout.tryCreateCached(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        gap: 2,
      )!;
      expect(cache.layoutBuildCount, 2);
      expect(cache.activeLeases, 4);
      expect(cached.size, original.size);
      expect(cached.baseline, original.baseline);
      expect(cached.baseOffset, original.baseOffset);
      expect(cached.annotationOffset, original.annotationOffset);
      expect(
        cached.projectionFor(ForumBodyRubyPart.annotation),
        same(input.annotation.projection),
      );
      expect(
        cached.selectionBoxes(
          part: ForumBodyRubyPart.base,
          startUtf16: 0,
          endUtf16: 11,
        ),
        original.selectionBoxes(
          part: ForumBodyRubyPart.base,
          startUtf16: 0,
          endUtf16: 11,
        ),
      );
      original.close();
      expect(cached.isActive, isTrue);
      cached.close();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'empty annotation needs only a cached base and preserves its empty source projection',
    () {
      final input = rubyPairInput(annotation: '');
      cache.acquire(content: input.base, width: 100).release();
      final cached = ForumBodyRubyGroupLayout.tryCreateCached(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      )!;
      expect(cached.hasAnnotation, isFalse);
      expect(cache.layoutBuildCount, 1);
      expect(cache.activeLeases, 1);
      expect(
        cached.projectionFor(ForumBodyRubyPart.annotation),
        same(input.annotation.projection),
      );
      cached.close();
    },
  );

  test(
    'adoption transfers existing handles with no lookup, scaling or native build',
    () {
      final input = rubyPairInput();
      final base = cache.acquire(content: input.base, width: 100);
      final annotation = cache.acquire(content: input.annotation, width: 100);
      final hits = cache.hitCount;
      final group = ForumBodyRubyGroupLayout.adopt(
        cache: cache,
        baseLease: base,
        annotation: input.annotation,
        annotationLease: annotation,
        gap: 2,
      );
      expect(cache.layoutBuildCount, 2);
      expect(cache.hitCount, hits);
      expect(cache.activeLeases, 2);
      expect(group.size, const Size(40, 32));
      group.close();
      group.close();
      expect(base.isActive, isFalse);
      expect(annotation.isActive, isFalse);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'failed adoption releases only supplied handles and preserves external aliases',
    () {
      final input = rubyPairInput();
      final external = cache.acquire(content: input.base, width: 100);
      final base = cache.acquire(content: input.base, width: 100);
      final annotation = cache.acquire(content: input.annotation, width: 100);
      final otherInputObject = rubyPairInput();
      expect(
        () => ForumBodyRubyGroupLayout.adopt(
          cache: cache,
          baseLease: base,
          annotation: otherInputObject.annotation,
          annotationLease: annotation,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(external.isActive, isTrue);
      expect(base.isActive, isFalse);
      expect(annotation.isActive, isFalse);
      expect(cache.activeLeases, 1);
      external.release();
    },
  );

  test(
    'owner proof prevents adopting another owner or retired native handles',
    () {
      final input = rubyPairInput();
      final foreign = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(foreign.close);
      final base = cache.acquire(content: input.base, width: 100);
      final annotation = foreign.acquire(content: input.annotation, width: 100);
      expect(cache.ownsLease(base), isTrue);
      expect(cache.ownsLease(annotation), isFalse);
      expect(
        () => ForumBodyRubyGroupLayout.adopt(
          cache: cache,
          baseLease: base,
          annotation: input.annotation,
          annotationLease: annotation,
        ),
        throwsStateError,
      );
      expect(cache.activeLeases, 0);
      expect(foreign.activeLeases, 0);
      final retired = cache.acquire(content: input.base, width: 100);
      retired.release();
      expect(cache.ownsLease(retired), isFalse);
      expect(
        () => ForumBodyRubyGroupLayout.adopt(
          cache: cache,
          baseLease: retired,
          annotation: rubyPairInput(annotation: '').annotation,
        ),
        throwsStateError,
      );
      cache.close();
      expect(cache.ownsLease(retired), isFalse);
    },
  );

  test(
    'cached lookup still validates geometry and releases failed completed acquisitions',
    () {
      final input = rubyPairInput();
      cache.acquire(content: input.base, width: 100).release();
      cache.acquire(content: input.annotation, width: 100).release();
      expect(
        () => ForumBodyRubyGroupLayout.tryCreateCached(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
          gap: double.nan,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(
        () => ForumBodyRubyGroupLayout.tryCreateCached(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
          maxWidth: 10,
        ),
        throwsA(
          isA<ForumBodyRubyGroupException>().having(
            (error) => error.failure,
            'natural width overflow',
            ForumBodyRubyGroupFailure.overflow,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 2);
      expect(cache.activeLeases, 0);
      cache.close();
      expect(
        () => ForumBodyRubyGroupLayout.tryCreateCached(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'missing or unexpected annotation handles fail and release transferred pins',
    () {
      final input = rubyPairInput();
      var base = cache.acquire(content: input.base, width: 100);
      expect(
        () => ForumBodyRubyGroupLayout.adopt(
          cache: cache,
          baseLease: base,
          annotation: input.annotation,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(cache.activeLeases, 0);
      base = cache.acquire(content: input.base, width: 100);
      final annotation = cache.acquire(content: input.annotation, width: 100);
      final empty = rubyPairInput(annotation: '').annotation;
      expect(
        () => ForumBodyRubyGroupLayout.adopt(
          cache: cache,
          baseLease: base,
          annotation: empty,
          annotationLease: annotation,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(cache.activeLeases, 0);
    },
  );
}
