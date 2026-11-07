import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

ForumBodyPreparationInput _input(String text, {String conversion = 'none'}) =>
    ForumBodyPreparationInput(
      html: '<p>$text</p>',
      sourceId: 'cache-test',
      conversionIdentity: conversion,
    );

void main() {
  test('completed inputs have bounded LRU and exact conversion identities', () {
    final cache = ForumNativeBodyCache(maxDocuments: 2);
    addTearDown(cache.close);
    final inputs = ['a', 'b', 'c'].map(_input).toList();
    for (final input in inputs.take(2)) {
      cache.rememberDocument(
        input.identity,
        input.prepareSynchronously(),
        codeUnits: input.html.length,
      );
    }
    expect(cache.documentFor(inputs.first.identity), isNotNull);
    cache.rememberDocument(
      inputs.last.identity,
      inputs.last.prepareSynchronously(),
      codeUnits: inputs.last.html.length,
    );
    expect(cache.documentCount, 2);
    expect(cache.documentFor(inputs[1].identity), isNull);
    expect(cache.documentFor(inputs.first.identity), isNotNull);
    expect(
      cache.documentFor(_input('a', conversion: 'converted').identity),
      isNull,
    );
    final large = _input('large');
    cache.rememberDocument(
      large.identity,
      large.prepareSynchronously(),
      codeUnits: cache.maxDocumentEstimatedBytes,
    );
    expect(cache.documentCount, 2);
    expect(
      cache.documentEstimatedBytes,
      lessThan(cache.maxDocumentEstimatedBytes),
    );
    cache.trim();
    expect(cache.documentCount, 0);
    expect(cache.paragraphs.isClosed, false);
  });

  test(
    'remounted consumer synchronously reuses an accepted background result',
    () async {
      final cache = ForumNativeBodyCache();
      addTearDown(cache.close);
      final result = Completer<ForumBodyDocument>();
      var jobs = 0;
      final executor = ForumBodyPreparationExecutor(
        codeUnitThreshold: 0,
        worker: (_) {
          jobs++;
          return result.future;
        },
      );
      addTearDown(executor.dispose);
      final input = _input('reusable');
      final first = ForumBodyPreparationController(executor: executor);
      expect(first.resolve(input, owner: 'first', cache: cache), isNull);
      final document = input.prepareSynchronously();
      result.complete(document);
      await Future<void>.delayed(Duration.zero);
      expect(
        first.resolve(input, owner: 'first', cache: cache),
        same(document),
      );
      first.dispose();
      final next = ForumBodyPreparationController(executor: executor);
      addTearDown(next.dispose);
      expect(
        next.resolve(input, owner: 'second', cache: cache),
        same(document),
      );
      expect(jobs, 1);
    },
  );

  test('retired async result cannot populate the page cache', () async {
    final cache = ForumNativeBodyCache();
    final result = Completer<ForumBodyDocument>();
    final executor = ForumBodyPreparationExecutor(
      codeUnitThreshold: 0,
      worker: (_) => result.future,
    );
    addTearDown(executor.dispose);
    final controller = ForumBodyPreparationController(executor: executor);
    final input = _input('obsolete');
    controller.resolve(input, owner: 'old', cache: cache);
    controller.dispose();
    cache.close();
    result.complete(input.prepareSynchronously());
    await Future<void>.delayed(Duration.zero);
    expect(cache.documentCount, 0);
    expect(cache.paragraphs.isClosed, true);
    expect(cache.documentFor(input.identity), isNull);
  });
}
