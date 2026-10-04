import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/application/composer_upload_session.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';

void main() {
  for (final error in [false, true]) {
    test(
      'synchronous ${error ? 'error' : 'completion'} can start a new run without losing its subscription',
      () async {
        final coordinator = _RunCoordinator(terminalOnListenIsError: error);
        final session = ComposerUploadSession(coordinator: coordinator);
        addTearDown(() async {
          await session.close();
          await coordinator.close();
        });
        final newEvents = <ComposerImageUploadEventType>[];
        List<String>? newAids;
        var oldSettlements = 0;

        void startNewRun() {
          oldSettlements += 1;
          expect(session.consumeBatch()!.localIds, ['old']);
          session.start(
            fid: '33',
            attachments: [_attachment('new')],
            anchor: null,
            onEvent: (event) {
              newEvents.add(event.type);
              if (event.type == ComposerImageUploadEventType.completed) {
                newAids = session.consumeBatch()!.successfulAids([
                  _attachment('new', aid: 'fresh'),
                ]);
              }
            },
            onError: (_, _) => fail('new run must stay subscribed'),
          );
        }

        session.start(
          fid: '33',
          attachments: [_attachment('old')],
          anchor: null,
          onEvent: (event) {
            expect(error, isFalse);
            expect(event.type, ComposerImageUploadEventType.completed);
            startNewRun();
          },
          onError: (_, _) {
            expect(error, isTrue);
            startNewRun();
          },
        );
        expect(oldSettlements, 1);
        await _drain();
        expect(coordinator.cancelledSubscriptions, [1, 0]);
        coordinator.runs[1].add(
          const ComposerImageUploadEvent.started(
            localId: 'new',
            current: 1,
            total: 1,
          ),
        );
        coordinator.runs[1].add(
          const ComposerImageUploadEvent.completed(total: 1),
        );
        await _drain();
        expect(newEvents, [
          ComposerImageUploadEventType.started,
          ComposerImageUploadEventType.completed,
        ]);
        expect(newAids, ['fresh']);
        expect(session.consumeBatch(), isNull);
        await session.close();
        expect(coordinator.cancelledSubscriptions, [1, 1]);
      },
    );
  }

  test(
    'completion consumes one batch in picker order with successful aid dedupe',
    () async {
      final coordinator = _RunCoordinator();
      final session = ComposerUploadSession(coordinator: coordinator);
      addTearDown(() async {
        await session.close();
        await coordinator.close();
      });
      final received = <ComposerImageUploadEvent>[];
      List<String>? aids;
      session.start(
        fid: '33',
        attachments: [
          _attachment('a'),
          _attachment('b'),
          _attachment('c'),
          _attachment('d'),
        ],
        anchor: null,
        onEvent: (event) {
          received.add(event);
          if (event.type == ComposerImageUploadEventType.completed) {
            final batch = session.consumeBatch()!;
            aids = batch.successfulAids([
              _attachment('d'),
              _attachment('c', aid: '30'),
              _attachment('b', aid: ' 10 '),
              _attachment('a', aid: '10'),
            ]);
          }
        },
        onError: (_, _) => fail('unexpected upload error'),
      );
      coordinator.runs.single.add(
        const ComposerImageUploadEvent.completed(total: 4),
      );
      await _drain();
      expect(aids, ['10', '30']);
      expect(session.consumeBatch(), isNull);
      coordinator.runs.single.add(
        const ComposerImageUploadEvent.started(
          localId: 'late',
          current: 1,
          total: 4,
        ),
      );
      coordinator.runs.single.add(
        const ComposerImageUploadEvent.completed(total: 4),
      );
      await _drain();
      expect(received, hasLength(1));
    },
  );

  test(
    'error consumes partial successes and rejects later completion or progress',
    () async {
      final coordinator = _RunCoordinator();
      final session = ComposerUploadSession(coordinator: coordinator);
      addTearDown(() async {
        await session.close();
        await coordinator.close();
      });
      var events = 0;
      var errors = 0;
      List<String>? aids;
      session.start(
        fid: '33',
        attachments: [_attachment('a'), _attachment('b')],
        anchor: null,
        onEvent: (_) {
          events += 1;
        },
        onError: (_, _) {
          errors += 1;
          aids = session.consumeBatch()!.successfulAids([
            _attachment('a', aid: '10'),
            _attachment('b'),
          ]);
        },
      );
      coordinator.runs.single.addError(StateError('controlled stream error'));
      await _drain();
      coordinator.runs.single.add(
        const ComposerImageUploadEvent.completed(total: 2),
      );
      coordinator.runs.single.add(
        const ComposerImageUploadEvent.progress(
          localId: 'a',
          current: 1,
          total: 2,
          progress: .9,
        ),
      );
      await _drain();
      expect(errors, 1);
      expect(events, 0);
      expect(aids, ['10']);
      expect(session.consumeBatch(), isNull);
    },
  );

  test(
    'cancel invalidates a delayed selection while a new selection can start',
    () async {
      final coordinator = _RunCoordinator();
      final session = ComposerUploadSession(coordinator: coordinator);
      final oldSelection = session.captureSelectionValidity();
      await session.cancel();
      expect(oldSelection(), isFalse);
      expect(session.captureSelectionValidity()(), isTrue);
      await session.close();
      expect(session.captureSelectionValidity()(), isFalse);
      session.start(
        fid: '33',
        attachments: [_attachment('late')],
        anchor: null,
        onEvent: (_) => fail('closed upload event'),
        onError: (_, _) => fail('closed upload error'),
      );
      expect(coordinator.runs, isEmpty);
      await coordinator.close();
    },
  );

  test('cancelled run cannot consume or settle a newer active batch', () async {
    final coordinator = _RunCoordinator();
    final session = ComposerUploadSession(coordinator: coordinator);
    addTearDown(() async {
      await session.close();
      await coordinator.close();
    });
    final received = <String>[];
    void start(String localId) => session.start(
      fid: '33',
      attachments: [_attachment(localId)],
      anchor: null,
      onEvent: (event) {
        received.add(event.localId);
        if (event.type == ComposerImageUploadEventType.completed) {
          received.add(session.consumeBatch()!.localIds.single);
        }
      },
      onError: (_, _) => fail('unexpected upload error'),
    );
    start('old');
    await session.cancel();
    start('new');
    coordinator.runs[0].add(const ComposerImageUploadEvent.completed(total: 1));
    coordinator.runs[1].add(
      const ComposerImageUploadEvent.started(
        localId: 'new',
        current: 1,
        total: 1,
      ),
    );
    coordinator.runs[1].add(const ComposerImageUploadEvent.completed(total: 1));
    await _drain();
    expect(received, ['new', '', 'new']);
    expect(session.consumeBatch(), isNull);
  });

  test(
    'synchronous on-listen close cancels the subscription returned afterwards',
    () async {
      final coordinator = _EarlyEventCoordinator();
      final session = ComposerUploadSession(coordinator: coordinator);
      Future<void>? closing;
      session.start(
        fid: '33',
        attachments: [_attachment('first')],
        anchor: null,
        onEvent: (_) {
          closing = session.close();
        },
        onError: (_, _) => fail('unexpected upload error'),
      );
      await closing;
      await _drain();
      expect(coordinator.cancelledSubscriptions, 1);
      expect(coordinator.cancelCalls, 1);
      expect(session.consumeBatch(), isNull);
      await coordinator.events.close();
    },
  );
}

ComposerImageAttachment _attachment(String localId, {String? aid}) =>
    ComposerImageAttachment(
      localId: localId,
      localPath: '/$localId.jpg',
      fileName: '$localId.jpg',
      mimeType: 'image/jpeg',
      order: 0,
      aid: aid,
      status: aid == null
          ? ComposerImageAttachmentStatus.local
          : ComposerImageAttachmentStatus.uploaded,
    );

Future<void> _drain() => Future<void>.delayed(Duration.zero);

final class _RunCoordinator implements ComposerImageUploadCoordinator {
  _RunCoordinator({this.terminalOnListenIsError});
  final bool? terminalOnListenIsError;
  final runs = <StreamController<ComposerImageUploadEvent>>[];
  final cancelledSubscriptions = <int>[];

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) {
    final index = runs.length;
    final earlyTerminal = index == 0 && terminalOnListenIsError != null;
    final run = StreamController<ComposerImageUploadEvent>.broadcast(
      sync: earlyTerminal,
    );
    runs.add(run);
    cancelledSubscriptions.add(0);
    run.onCancel = () {
      cancelledSubscriptions[index] += 1;
    };
    if (earlyTerminal) {
      return _EarlyEventStream(
        run,
        emitOnListen: () {
          if (terminalOnListenIsError!) {
            run.addError(StateError('controlled synchronous upload error'));
          } else {
            run.add(const ComposerImageUploadEvent.completed(total: 1));
          }
        },
      );
    }
    return run.stream;
  }

  @override
  void cancel() {}

  Future<void> close() async {
    for (final run in runs) {
      await run.close();
    }
  }
}

final class _EarlyEventCoordinator implements ComposerImageUploadCoordinator {
  _EarlyEventCoordinator() {
    events.onCancel = () {
      cancelledSubscriptions += 1;
    };
  }
  final events = StreamController<ComposerImageUploadEvent>(sync: true);
  int cancelledSubscriptions = 0;
  int cancelCalls = 0;

  @override
  void cancel() {
    cancelCalls += 1;
  }

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) => _EarlyEventStream(events);
}

final class _EarlyEventStream extends Stream<ComposerImageUploadEvent> {
  _EarlyEventStream(this.controller, {this.emitOnListen});
  final StreamController<ComposerImageUploadEvent> controller;
  final void Function()? emitOnListen;

  @override
  StreamSubscription<ComposerImageUploadEvent> listen(
    void Function(ComposerImageUploadEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    final emit = emitOnListen;
    if (emit != null) {
      emit();
    } else {
      controller.add(
        const ComposerImageUploadEvent.started(
          localId: 'first',
          current: 1,
          total: 1,
        ),
      );
    }
    return subscription;
  }
}
