import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:y300/features/cache/data/services/image_cache_diagnostic_recorder.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

void main() {
  test('first failure logs immediately with its sanitized fields', () {
    final capture = _Capture(now: () => DateTime.utc(2026));
    capture.recorder.recordFailure(_event(bytesReceived: 23));

    expect(capture.lines, hasLength(1));
    expect(capture.lines.single, startsWith('[ImageCache][failure]'));
    expect(capture.lines.single, contains('stage=download'));
    expect(capture.lines.single, contains('kind=notFound'));
    expect(capture.lines.single, contains('reason=resource_not_found'));
    expect(capture.lines.single, contains('bytesReceived=23'));
    expect(capture.lines.single, contains('elapsedMs=53'));
    expect(capture.lines.single, isNot(contains('suppressedCount=')));
  });

  test('45 repeats log once and report 44 suppressed at the next window', () {
    var now = DateTime.utc(2026);
    final capture = _Capture(now: () => now);
    for (var attempt = 0; attempt < 45; attempt++) {
      capture.recorder.recordFailure(
        _event(elapsedMilliseconds: attempt, bytesReceived: attempt),
      );
    }
    expect(capture.lines, hasLength(1));
    now = now.add(const Duration(seconds: 30));
    // Window expiry is passive: only a new failure can emit its summary.
    expect(capture.lines, hasLength(1));
    capture.recorder.recordFailure(_event(elapsedMilliseconds: 70));
    expect(capture.lines, hasLength(2));
    expect(capture.lines.last, contains('suppressedCount=44'));
    expect(capture.lines.last, contains('elapsedMs=70'));
    now = now.add(const Duration(seconds: 30));
    capture.recorder.recordFailure(_event());
    expect(capture.lines, hasLength(3));
    expect(capture.lines.last, isNot(contains('suppressedCount=')));
  });

  test('every classification field separates groups for the same image', () {
    final capture = _Capture(now: () => DateTime.utc(2026));
    final events = [
      _event(),
      _event(fingerprint: 'different-fingerprint'),
      _event(stage: ImageCacheDiagnosticStage.decode),
      _event(kind: ImageCacheDiagnosticFailureKind.unauthorized),
      _event(reason: 'resource_unauthorized'),
      _event(exceptionType: 'StateError'),
      _event(ownerType: 'comic'),
      _event(role: 'thread_attachment'),
    ];
    for (final event in events) {
      capture.recorder.recordFailure(event);
      capture.recorder.recordFailure(event);
    }
    expect(capture.lines, hasLength(events.length));
  });

  test('a repeat near expiry does not extend the fixed window', () {
    final origin = DateTime.utc(2026);
    var now = origin;
    final capture = _Capture(now: () => now);
    capture.recorder.recordFailure(_event());
    now = origin.add(const Duration(seconds: 29));
    capture.recorder.recordFailure(_event());
    expect(capture.lines, hasLength(1));
    now = origin.add(const Duration(seconds: 30));
    capture.recorder.recordFailure(_event());
    expect(capture.lines, hasLength(2));
    expect(capture.lines.last, contains('suppressedCount=1'));
  });

  test('clock rollback reopens windows even after their original start', () {
    final origin = DateTime.utc(2026);
    var now = origin.add(const Duration(seconds: 10));
    final capture = _Capture(now: () => now);
    capture.recorder.recordFailure(_event());
    capture.recorder.recordFailure(_event(fingerprint: 'other-image'));
    now = origin.add(const Duration(seconds: 20));
    capture.recorder.recordFailure(_event());
    now = origin.add(const Duration(seconds: 19));
    capture.recorder.recordFailure(_event());
    expect(capture.lines, hasLength(3));
    expect(capture.lines.last, contains('suppressedCount=1'));
    capture.recorder.recordFailure(_event(fingerprint: 'other-image'));
    expect(capture.lines, hasLength(4));
    now = origin.add(const Duration(seconds: 48));
    capture.recorder.recordFailure(_event());
    expect(capture.lines, hasLength(4));
    now = origin.add(const Duration(seconds: 49));
    capture.recorder.recordFailure(_event());
    expect(capture.lines, hasLength(5));
    expect(capture.lines.last, contains('suppressedCount=1'));
  });

  test('capacity evicts old windows without growing on suppressed hits', () {
    final capture = _Capture(now: () => DateTime.utc(2026), maxBuckets: 2);
    capture.recorder.recordFailure(_event(fingerprint: 'a'));
    capture.recorder.recordFailure(_event(fingerprint: 'b'));
    capture.recorder.recordFailure(_event(fingerprint: 'a'));
    capture.recorder.recordFailure(_event(fingerprint: 'c'));
    capture.recorder.recordFailure(_event(fingerprint: 'b'));
    expect(capture.lines, hasLength(3));
    capture.recorder.recordFailure(_event(fingerprint: 'a'));
    expect(capture.lines, hasLength(4));
    expect(capture.lines.last, contains('cacheKeyHash=a'));
    expect(capture.lines.last, isNot(contains('suppressedCount=')));
  });

  test('the default capacity bounds groups to 256', () {
    final capture = _Capture(now: () => DateTime.utc(2026));
    for (var image = 0; image < 257; image++) {
      capture.recorder.recordFailure(_event(fingerprint: 'image-$image'));
    }
    capture.recorder.recordFailure(_event(fingerprint: 'image-256'));
    expect(capture.lines, hasLength(257));
    capture.recorder.recordFailure(_event(fingerprint: 'image-0'));
    expect(capture.lines, hasLength(258));
  });

  for (final disabledByCapacity in [true, false]) {
    test(
      '${disabledByCapacity ? 'zero capacity' : 'zero duration'} disables suppression',
      () {
        final capture = _Capture(
          // A disabled policy does not need a clock or retain any windows.
          now: () => throw StateError('clock should not be consulted'),
          maxBuckets: disabledByCapacity ? 0 : 256,
          suppressionWindow: disabledByCapacity
              ? const Duration(seconds: 30)
              : Duration.zero,
        );
        for (var attempt = 0; attempt < 45; attempt++) {
          capture.recorder.recordFailure(_event());
        }
        expect(capture.lines, hasLength(45));
        expect(capture.lines.join('\n'), isNot(contains('suppressedCount=')));
      },
    );
  }

  test('summaries never expose cache keys, paths or exception payloads', () {
    var now = DateTime.utc(2026);
    final capture = _Capture(now: () => now);
    const privateKey =
        'https://example.invalid/private.png?token=private-secret';
    final event = buildImageCacheFailureDiagnostic(
      stage: ImageCacheDiagnosticStage.download,
      cacheKey: privateKey,
      ownerType: ImageCacheOwnerType.thread,
      role: ImageCacheRole.threadInline,
      error: const FileSystemException(
        'private-server-payload',
        'C:/private-image-path/body.png',
      ),
      elapsed: const Duration(milliseconds: 12),
    );
    for (var attempt = 0; attempt < 45; attempt++) {
      capture.recorder.recordFailure(event);
    }
    now = now.add(const Duration(seconds: 30));
    capture.recorder.recordFailure(event);
    final output = capture.lines.join('\n');
    expect(capture.lines, hasLength(2));
    expect(output, contains('suppressedCount=44'));
    expect(
      output,
      contains(ImageCacheFailureDiagnostic.fingerprint(privateKey)),
    );
    expect(output, isNot(contains('https://')));
    expect(output, isNot(contains('private-secret')));
    expect(output, isNot(contains('private-server-payload')));
    expect(output, isNot(contains('private-image-path')));
  });

  test('clock failure is isolated and a later call can still log', () {
    var clockFails = true;
    final capture = _Capture(
      now: () {
        if (clockFails) throw StateError('controlled clock failure');
        return DateTime.utc(2026);
      },
    );
    expect(() => capture.recorder.recordFailure(_event()), returnsNormally);
    clockFails = false;
    capture.recorder.recordFailure(_event());
    expect(capture.lines, hasLength(1));
  });

  test('logger failure is isolated without installing a silent window', () {
    final printer = _ThrowingPrinter();
    final logger = Logger(filter: ProductionFilter(), printer: printer);
    addTearDown(logger.close);
    final recorder = LoggerImageCacheDiagnosticRecorder(
      logger,
      now: () => DateTime.utc(2026),
    );
    expect(() => recorder.recordFailure(_event()), returnsNormally);
    expect(() => recorder.recordFailure(_event()), returnsNormally);
    expect(printer.attempts, 2);
  });
}

ImageCacheFailureDiagnostic _event({
  String fingerprint = '56acd74ff029a984',
  ImageCacheDiagnosticStage stage = ImageCacheDiagnosticStage.download,
  ImageCacheDiagnosticFailureKind kind =
      ImageCacheDiagnosticFailureKind.notFound,
  String reason = 'resource_not_found',
  String exceptionType = 'ForumResourceFileServiceException',
  String ownerType = 'thread',
  String role = 'thread_inline',
  int elapsedMilliseconds = 53,
  int? bytesReceived,
}) => ImageCacheFailureDiagnostic(
  stage: stage,
  ownerType: ownerType,
  role: role,
  cacheKeyFingerprint: fingerprint,
  failureKind: kind,
  reasonCode: reason,
  exceptionType: exceptionType,
  elapsedMilliseconds: elapsedMilliseconds,
  bytesReceived: bytesReceived,
);

class _Capture {
  _Capture({
    DateTime Function()? now,
    Duration suppressionWindow = const Duration(seconds: 30),
    int maxBuckets = 256,
  }) {
    final logger = Logger(
      filter: ProductionFilter(),
      printer: _MessagePrinter(),
      output: output,
      level: Level.warning,
    );
    addTearDown(logger.close);
    recorder = LoggerImageCacheDiagnosticRecorder(
      logger,
      now: now,
      suppressionWindow: suppressionWindow,
      maxBuckets: maxBuckets,
    );
  }

  final output = _MemoryOutput();
  late final LoggerImageCacheDiagnosticRecorder recorder;
  List<String> get lines => output.lines;
}

class _MemoryOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

class _MessagePrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) => [event.message.toString()];
}

class _ThrowingPrinter extends LogPrinter {
  int attempts = 0;

  @override
  List<String> log(LogEvent event) {
    attempts++;
    throw StateError('controlled printer failure');
  }
}
