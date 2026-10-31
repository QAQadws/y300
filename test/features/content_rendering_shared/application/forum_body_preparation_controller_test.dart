import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

ForumBodyPreparationInput _input(String text) => ForumBodyPreparationInput(
  html: '<p>$text</p>',
  sourceId: 'synthetic:body',
  conversionIdentity: 'none',
);

Future<void> _drain() => Future<void>.delayed(Duration.zero);

final class _Worker {
  final inputs = <ForumBodyPreparationInput>[];
  final results = <Completer<ForumBodyDocument>>[];
  Future<ForumBodyDocument> call(ForumBodyPreparationInput input) {
    inputs.add(input);
    final result = Completer<ForumBodyDocument>();
    results.add(result);
    return result.future;
  }

  void complete(int index) =>
      results[index].complete(inputs[index].prepareSynchronously());
}

void main() {
  test(
    'A to B to A shares work but accepts only the current generation',
    () async {
      final worker = _Worker();
      final scheduler = ForumPreparationScheduler(maxConcurrent: 2);
      addTearDown(scheduler.dispose);
      final executor = ForumBodyPreparationExecutor(
        scheduler: scheduler,
        codeUnitThreshold: 0,
        worker: worker.call,
      );
      addTearDown(executor.dispose);
      final controller = ForumBodyPreparationController(executor: executor);
      addTearDown(controller.dispose);
      final owner = Object();
      var notifications = 0;
      controller.addListener(() => notifications++);
      final a = _input('A');
      final b = _input('B');
      expect(controller.resolve(a, owner: owner), isNull);
      expect(controller.resolve(b, owner: owner), isNull);
      expect(controller.resolve(a, owner: owner), isNull);
      expect(worker.inputs, hasLength(2));
      worker.complete(1);
      await _drain();
      expect(notifications, 0);
      expect(controller.resolve(a, owner: owner), isNull);
      worker.complete(0);
      await _drain();
      expect(notifications, 1);
      final document = controller.resolve(a, owner: owner)!;
      expect(document.sourceText, 'A');
      expect(controller.resolve(a, owner: owner), same(document));
      expect(worker.inputs, hasLength(2));
    },
  );

  test('owner replacement retires completed state without duplicating in-flight work', () async {
    final worker = _Worker();
    final executor = ForumBodyPreparationExecutor(
      codeUnitThreshold: 0,
      worker: worker.call,
    );
    addTearDown(executor.dispose);
    final controller = ForumBodyPreparationController(executor: executor);
    addTearDown(controller.dispose);
    final input = _input('same input');
    final first = Object();
    final second = Object();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.resolve(input, owner: first);
    controller.resolve(input, owner: second);
    expect(worker.inputs, hasLength(1));
    worker.complete(0);
    await _drain();
    expect(notifications, 1);
    expect(controller.resolve(input, owner: second), isNotNull);
    final third = Object();
    expect(controller.resolve(input, owner: third), isNull);
    expect(worker.inputs, hasLength(2));
    worker.complete(1);
    await _drain();
    expect(notifications, 2);
  });

  test(
    'capacity wait follows latest request and reset removes its listener',
    () async {
      final worker = _Worker();
      final scheduler = ForumPreparationScheduler(maxQueued: 0);
      addTearDown(scheduler.dispose);
      final executor = ForumBodyPreparationExecutor(
        scheduler: scheduler,
        codeUnitThreshold: 0,
        worker: worker.call,
      );
      addTearDown(executor.dispose);
      final blocker = executor.tryAcquire(_input('blocker'))!;
      final controller = ForumBodyPreparationController(executor: executor);
      addTearDown(controller.dispose);
      final owner = Object();
      controller.resolve(_input('obsolete'), owner: owner);
      final current = _input('latest');
      controller.resolve(current, owner: owner);
      expect(worker.inputs, hasLength(1));
      worker.complete(0);
      await blocker.future;
      blocker.release();
      await _drain();
      expect(worker.inputs, hasLength(2));
      expect(worker.inputs.last.html, current.html);
      final waiter = ForumBodyPreparationController(executor: executor);
      waiter.resolve(_input('retired waiter'), owner: owner);
      waiter.reset();
      waiter.dispose();
      worker.complete(1);
      await _drain();
      expect(controller.resolve(current, owner: owner), isNotNull);
      expect(worker.inputs, hasLength(2));
    },
  );

  test(
    'reset cancels queued work while another consumer keeps a shared job',
    () async {
      final worker = _Worker();
      final executor = ForumBodyPreparationExecutor(
        codeUnitThreshold: 0,
        worker: worker.call,
      );
      addTearDown(executor.dispose);
      final blocker = executor.tryAcquire(_input('blocker'))!;
      final first = ForumBodyPreparationController(executor: executor);
      final second = ForumBodyPreparationController(executor: executor);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final input = _input('shared');
      first.resolve(input, owner: 'first');
      second.resolve(input, owner: 'second');
      first.reset();
      expect(executor.queuedCount, 1);
      worker.complete(0);
      await blocker.future;
      blocker.release();
      await _drain();
      worker.complete(1);
      await _drain();
      expect(second.resolve(input, owner: 'second')!.sourceText, 'shared');
      expect(first.hasError, isFalse);
    },
  );

  test(
    'retired failure is ignored and current failure can retry after reset',
    () async {
      final worker = _Worker();
      final scheduler = ForumPreparationScheduler(maxConcurrent: 2);
      addTearDown(scheduler.dispose);
      final executor = ForumBodyPreparationExecutor(
        scheduler: scheduler,
        codeUnitThreshold: 0,
        worker: worker.call,
      );
      addTearDown(executor.dispose);
      final controller = ForumBodyPreparationController(executor: executor);
      addTearDown(controller.dispose);
      controller.resolve(_input('old'), owner: 'owner');
      final current = _input('current');
      controller.resolve(current, owner: 'owner');
      worker.results[0].completeError(StateError('retired'));
      await _drain();
      expect(controller.hasError, isFalse);
      worker.results[1].completeError(
        const ForumBodyParseException(ForumBodyParseFailure.nodeLimit),
      );
      await _drain();
      expect(controller.hasError, isTrue);
      expect(
        () => controller.resolve(current, owner: 'owner'),
        throwsA(isA<ForumBodyParseException>()),
      );
      controller.reset();
      expect(controller.resolve(current, owner: 'owner'), isNull);
      worker.complete(2);
      await _drain();
      expect(controller.hasError, isFalse);
      expect(controller.resolve(current, owner: 'owner'), isNotNull);
    },
  );

  test(
    'dispose ignores late success and late error without notification',
    () async {
      for (final fail in [false, true]) {
        final worker = _Worker();
        final executor = ForumBodyPreparationExecutor(
          codeUnitThreshold: 0,
          worker: worker.call,
        );
        final controller = ForumBodyPreparationController(executor: executor);
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.resolve(_input('late'), owner: 'owner');
        controller.dispose();
        if (fail) {
          worker.results.single.completeError(StateError('late'));
        } else {
          worker.complete(0);
        }
        await _drain();
        expect(notifications, 0);
        expect(
          () => controller.resolve(_input('new'), owner: 'owner'),
          throwsStateError,
        );
        executor.dispose();
      }
    },
  );

  test(
    'small documents prepare synchronously and provenance changes identity',
    () {
      final executor = ForumBodyPreparationExecutor();
      addTearDown(executor.dispose);
      final controller = ForumBodyPreparationController(executor: executor);
      addTearDown(controller.dispose);
      final input = _input('字');
      final document = controller.resolve(input, owner: 'owner')!;
      expect(controller.resolve(input, owner: 'owner'), same(document));
      final converted = controller.resolve(
        ForumBodyPreparationInput(
          html: input.html,
          sourceId: input.sourceId,
          conversionIdentity: 'traditional',
        ),
        owner: 'owner',
      )!;
      expect(converted.identity, isNot(document.identity));
      expect(executor.activeCount, 0);
    },
  );
}
