import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';

void main() {
  test('decode concurrency never exceeds configured limit', () async {
    final scheduler = LibraryCoverDecodeScheduler(maxConcurrent: 2);
    final firstGate = _DecodeGate();
    final secondGate = _DecodeGate();
    final thirdGate = _DecodeGate();

    final first = scheduler.schedule(key: 'first', action: firstGate.run);
    final second = scheduler.schedule(key: 'second', action: secondGate.run);
    final third = scheduler.schedule(key: 'third', action: thirdGate.run);

    await Future<void>.delayed(Duration.zero);
    expect(firstGate.started, isTrue);
    expect(secondGate.started, isTrue);
    expect(thirdGate.started, isFalse);

    firstGate.release();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(thirdGate.started, isTrue);

    secondGate.release();
    thirdGate.release();
    await Future.wait(<Future<ui.Codec>>[second, third]);
  });

  test('queued decodes run in FIFO order', () async {
    final scheduler = LibraryCoverDecodeScheduler(maxConcurrent: 1);
    final firstGate = _DecodeGate();
    final secondGate = _DecodeGate();
    final thirdGate = _DecodeGate();

    final first = scheduler.schedule(key: 'first', action: firstGate.run);
    final second = scheduler.schedule(key: 'second', action: secondGate.run);
    final third = scheduler.schedule(key: 'third', action: thirdGate.run);

    firstGate.release();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(secondGate.started, isTrue);
    expect(thirdGate.started, isFalse);

    secondGate.release();
    await second;
    await Future<void>.delayed(Duration.zero);
    expect(thirdGate.started, isTrue);

    thirdGate.release();
    await third;
  });

  test('same key shares one queued decode', () async {
    final scheduler = LibraryCoverDecodeScheduler(maxConcurrent: 1);
    final blocker = _DecodeGate();
    final shared = _DecodeGate();

    final blockerFuture = scheduler.schedule(
      key: 'blocker',
      action: blocker.run,
    );
    final first = scheduler.schedule(key: 'shared', action: shared.run);
    final second = scheduler.schedule(
      key: 'shared',
      action: () => throw StateError('single-flight action must be reused'),
    );

    expect(identical(first, second), isTrue);
    expect(shared.started, isFalse);

    blocker.release();
    await blockerFuture;
    await Future<void>.delayed(Duration.zero);
    expect(shared.started, isTrue);

    shared.release();
    await Future.wait(<Future<ui.Codec>>[first, second]);
  });

  test('failed decode releases its slot for the next request', () async {
    final scheduler = LibraryCoverDecodeScheduler(maxConcurrent: 1);
    final releaseFailure = Completer<void>();
    final nextGate = _DecodeGate();
    final failed = scheduler.schedule(
      key: 'failed',
      action: () async {
        await releaseFailure.future;
        throw StateError('decode failed');
      },
    );
    final failureExpectation = expectLater(failed, throwsStateError);
    final next = scheduler.schedule(key: 'next', action: nextGate.run);

    expect(nextGate.started, isFalse);
    releaseFailure.complete();
    await failureExpectation;
    await Future<void>.delayed(Duration.zero);
    expect(nextGate.started, isTrue);

    nextGate.release();
    await next;
  });
}

class _DecodeGate {
  final _release = Completer<void>();
  bool started = false;

  Future<ui.Codec> run() async {
    started = true;
    await _release.future;
    return ui.instantiateImageCodec(_onePixelPng);
  }

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
