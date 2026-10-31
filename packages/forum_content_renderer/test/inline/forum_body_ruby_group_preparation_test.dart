import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_pair_fixture.dart';

void _owner() {}

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
    'cold advances build one child each and transfer the complete pair once',
    () {
      final input = rubyPairInput();
      final prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
        gap: 2,
      );
      expect(cache.layoutBuildCount, 0);
      final first = prepare.advance();
      expect(first.partsPrepared, 1);
      expect(first.layoutsBuilt, 1);
      expect(first.isReady, isFalse);
      expect(prepare.preparedPartCount, 1);
      expect(cache.activeLeases, 1);
      expect(() => prepare.takeLayout(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.active);
      final second = prepare.advance();
      expect(second.partsPrepared, 1);
      expect(second.layoutsBuilt, 1);
      expect(second.isReady, isTrue);
      expect(second.madeProgress, isTrue);
      expect(cache.activeLeases, 2);
      expect(() => prepare.advance(), throwsStateError);
      expect(prepare.isReady, isTrue);
      final group = prepare.takeLayout();
      expect(prepare.state, ForumBodyRubyGroupPreparationState.transferred);
      expect(group.size, const Size(40, 32));
      prepare.close();
      expect(group.isActive, isTrue);
      expect(() => prepare.takeLayout(), throwsStateError);
      group.close();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'fully warm cached preparation completes without native construction',
    () {
      final input = rubyPairInput();
      cache.acquire(content: input.base, width: 100).release();
      cache.acquire(content: input.annotation, width: 100).release();
      final prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
      );
      expect(prepare.tryPrepareCached(), isTrue);
      expect(prepare.tryPrepareCached(), isTrue);
      expect(cache.layoutBuildCount, 2);
      expect(cache.activeLeases, 2);
      prepare.takeLayout().close();
      expect(cache.activeLeases, 0);
      final another = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
      );
      final step = another.advance();
      expect(step.layoutsBuilt, 0);
      expect(step.partsPrepared, 2);
      expect(step.isReady, isTrue);
      another.close();
    },
  );

  test(
    'cached partial work stays pinned and a later advance builds only the missing child',
    () {
      final input = rubyPairInput();
      final external = cache.acquire(content: input.base, width: 100);
      final prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
      );
      expect(prepare.tryPrepareCached(), isFalse);
      expect(prepare.preparedPartCount, 1);
      expect(cache.activeLeases, 2);
      expect(cache.layoutBuildCount, 1);
      final step = prepare.advance();
      expect(step.layoutsBuilt, 1);
      expect(step.partsPrepared, 1);
      expect(step.isReady, isTrue);
      prepare.close();
      expect(external.isActive, isTrue);
      expect(cache.activeLeases, 1);
      external.release();
    },
  );

  test(
    'empty annotation is a one-build transaction without a blank upper row',
    () {
      final input = rubyPairInput(annotation: '');
      final prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
        gap: 8,
      );
      expect(prepare.expectedPartCount, 1);
      final step = prepare.advance();
      expect(step.layoutsBuilt, 1);
      expect(step.isReady, isTrue);
      final group = prepare.takeLayout();
      expect(group.hasAnnotation, isFalse);
      expect(group.size, const Size(40, 20));
      expect(cache.activeLeases, 1);
      group.close();
    },
  );

  test(
    'external pins wait after a bounded whole-pair check and resume without rebuilding the base',
    () {
      final limited = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(limited.close);
      final input = rubyPairInput();
      final foreign = rubyPairInput(base: 'ZZ');
      final external = limited.acquire(content: foreign.base, width: 100);
      final prepare = ForumBodyRubyGroupPreparation(
        cache: limited,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
      );
      expect(prepare.advance().layoutsBuilt, 1);
      final blocked = prepare.advance();
      expect(blocked.waitingForLayoutBudget, isTrue);
      expect(blocked.partsInspected, 2);
      expect(blocked.partsPrepared, 0);
      expect(blocked.layoutsBuilt, 0);
      expect(blocked.madeProgress, isTrue);
      expect(prepare.waitingForLayoutBudget, isTrue);
      final again = prepare.advance();
      expect(again.partsInspected, 0);
      expect(again.waitingForLayoutBudget, isTrue);
      expect(again.madeProgress, isFalse);
      expect(limited.layoutBuildCount, 2);
      external.release();
      final ready = prepare.advance();
      expect(ready.layoutsBuilt, 1);
      expect(ready.isReady, isTrue);
      expect(prepare.waitingForLayoutBudget, isFalse);
      expect(limited.layoutBuildCount, 3);
      prepare.takeLayout().close();
      expect(limited.activeLeases, 0);
    },
  );

  test(
    'release during budget inspection does not wait for an already observed revision',
    () {
      final limited = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(limited.close);
      final foreign = rubyPairInput(base: 'ZZ');
      final one = limited.acquire(content: foreign.base, width: 100);
      final two = limited.acquire(content: foreign.annotation, width: 100);
      final input = rubyPairInput();
      var scales = 0;
      final prepare = ForumBodyRubyGroupPreparation(
        cache: limited,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
        textScaler: _Scaler((size) {
          if (++scales == 2) {
            one.release();
            two.release();
          }
          return size;
        }),
      );
      final step = prepare.advance();
      expect(step.partsInspected, 2);
      expect(step.waitingForLayoutBudget, isFalse);
      expect(step.layoutsBuilt, 0);
      expect(step.madeProgress, isTrue);
      expect(prepare.advance().layoutsBuilt, 1);
      prepare.close();
      expect(limited.activeLeases, 0);
    },
  );

  test(
    'a pair intrinsically exceeding entry or byte budget fails instead of waiting forever',
    () {
      final input = rubyPairInput();
      for (final limited in [
        ForumBodyParagraphCache(maxEntries: 1, maxEstimatedBytes: 1 << 20),
        ForumBodyParagraphCache(maxEntries: 8, maxEstimatedBytes: 7000),
      ]) {
        addTearDown(limited.close);
        final prepare = ForumBodyRubyGroupPreparation(
          cache: limited,
          base: input.base,
          annotation: input.annotation,
          ensureOwner: _owner,
        );
        expect(prepare.advance().layoutsBuilt, 1);
        expect(
          () => prepare.advance(),
          throwsA(
            isA<ForumBodyRubyGroupPreparationException>().having(
              (error) => error.failure,
              'whole pair footprint',
              ForumBodyRubyGroupPreparationFailure.intrinsicBudget,
            ),
          ),
        );
        expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
        expect(prepare.waitingForLayoutBudget, isFalse);
        expect(limited.activeLeases, 0);
        expect(limited.isClosed, isFalse);
        expect(() => prepare.tryPrepareCached(), throwsStateError);
      }
    },
  );

  test(
    'intrinsic pair failure under foreign pressure preserves the visible foreign lease',
    () {
      final limited = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(limited.close);
      final foreign = limited.acquire(
        content: rubyPairInput(base: 'ZZ').base,
        width: 100,
      );
      final input = rubyPairInput();
      final prepare = ForumBodyRubyGroupPreparation(
        cache: limited,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
      );
      expect(
        () => prepare.advance(),
        throwsA(isA<ForumBodyRubyGroupPreparationException>()),
      );
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(limited.layoutBuildCount, 1);
      expect(foreign.isActive, isTrue);
      expect(limited.activeLeases, 1);
      foreign.release();
    },
  );

  test(
    'closing cold, partial and ready cursors releases only their owned handles',
    () {
      final input = rubyPairInput();
      for (final advances in [0, 1, 2]) {
        cache.clearUnpinned();
        final prepare = ForumBodyRubyGroupPreparation(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
          ensureOwner: _owner,
        );
        for (var i = 0; i < advances; i++) {
          prepare.advance();
        }
        prepare.close();
        prepare.close();
        expect(prepare.state, ForumBodyRubyGroupPreparationState.closed);
        expect(cache.activeLeases, 0);
        expect(cache.isClosed, isFalse);
        expect(() => prepare.advance(), throwsStateError);
      }
    },
  );

  test('generation failure before the next child releases partial work', () {
    final input = rubyPairInput();
    var active = true;
    final prepare = ForumBodyRubyGroupPreparation(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
      ensureOwner: () {
        if (!active) throw StateError('retired generation');
      },
    );
    prepare.advance();
    active = false;
    expect(() => prepare.advance(), throwsStateError);
    expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
    expect(cache.activeLeases, 0);
    expect(cache.layoutBuildCount, 1);
    expect(cache.isClosed, isFalse);
  });

  test(
    'generation failure before transfer retires the prepared native pair',
    () {
      final input = rubyPairInput();
      var active = true;
      final prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: () {
          if (!active) throw StateError('retired generation');
        },
      );
      prepare.advance();
      prepare.advance();
      active = false;
      expect(() => prepare.takeLayout(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'cancellation during a cached miss is checked even when no handle is returned',
    () {
      final input = rubyPairInput();
      late ForumBodyRubyGroupPreparation prepare;
      prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
        textScaler: _Scaler((size) {
          prepare.close();
          return size;
        }),
      );
      expect(() => prepare.tryPrepareCached(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.closed);
      expect(cache.activeLeases, 0);
      expect(cache.layoutBuildCount, 0);
    },
  );

  test(
    'cancellation while native shaping releases the returned handle before publication',
    () {
      final input = rubyPairInput();
      late ForumBodyRubyGroupPreparation prepare;
      var calls = 0;
      prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
        textScaler: _Scaler((size) {
          if (++calls == 2) prepare.close();
          return size;
        }),
      );
      expect(() => prepare.advance(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.closed);
      expect(cache.activeLeases, 0);
      expect(cache.layoutBuildCount, 1);
      expect(cache.isClosed, isFalse);
      cache.clearUnpinned();
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'cancellation after adopting children cannot leak the not-yet-published group',
    () {
      final input = rubyPairInput();
      cache.acquire(content: input.base, width: 100).release();
      cache.acquire(content: input.annotation, width: 100).release();
      late ForumBodyRubyGroupPreparation prepare;
      var fullGuards = 0;
      prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: () {
          if (prepare.preparedPartCount == 2 && ++fullGuards == 2) {
            prepare.close();
          }
        },
      );
      expect(() => prepare.tryPrepareCached(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.closed);
      expect(cache.activeLeases, 0);
      expect(cache.layoutBuildCount, 2);
    },
  );

  test(
    'cache owner retirement invalidates ready and in-flight preparation',
    () {
      final input = rubyPairInput();
      final ready = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
      );
      ready.advance();
      ready.advance();
      cache.close();
      expect(() => ready.takeLayout(), throwsStateError);
      expect(ready.state, ForumBodyRubyGroupPreparationState.failed);
      expect(cache.activeLeases, 0);
      final inFlight = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(inFlight.close);
      var calls = 0;
      final prepare = ForumBodyRubyGroupPreparation(
        cache: inFlight,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
        textScaler: _Scaler((size) {
          if (++calls == 2) inFlight.close();
          return size;
        }),
      );
      expect(() => prepare.advance(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(inFlight.activeLeases, 0);
      expect(inFlight.estimatedRetainedBytes, 0);
    },
  );

  test(
    'reentrant preparation cannot issue multiple native requests in one operation',
    () {
      final input = rubyPairInput();
      late ForumBodyRubyGroupPreparation prepare;
      prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: () {
          prepare.advance();
        },
      );
      expect(() => prepare.advance(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(cache.layoutBuildCount, 0);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'geometry failure after the second child rolls back the complete transaction',
    () {
      final input = rubyPairInput();
      final prepare = ForumBodyRubyGroupPreparation(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
        maxWidth: 10,
      );
      expect(prepare.advance().layoutsBuilt, 1);
      expect(
        () => prepare.advance(),
        throwsA(
          isA<ForumBodyRubyGroupException>().having(
            (error) => error.failure,
            'group overflow',
            ForumBodyRubyGroupFailure.overflow,
          ),
        ),
      );
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(cache.layoutBuildCount, 2);
      expect(cache.activeLeases, 0);
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler(this.resolve);
  final double Function(double) resolve;
  @override
  double scale(double size) => resolve(size);
  @override
  double get textScaleFactor => 1;
}
