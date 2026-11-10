import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/application/post_edit_submission_coordinator.dart';
import 'package:y300/features/thread/domain/models/post_edit_submission_attempt.dart';

import '../test_support/post_edit_test_support.dart';

void main() {
  test(
    'host state publication can retire a command before its port starts',
    () async {
      final harness = _Harness();
      final request = harness.flow.submit(_attempt())!;
      harness.flow.invalidate();
      expect((await request).kind, PostEditSubmissionResolutionKind.superseded);
      expect(harness.commands, isEmpty);
      expect(harness.reads, isEmpty);
    },
  );

  test(
    'retired verification cannot claim a newer shared form-read generation',
    () async {
      final harness = _Harness(
        command: (_) => const DataCommandOutcomeUnknown(_unknown),
      );
      await harness.flow.submit(_attempt())!;
      final verification = harness.flow.verifyUncertain()!;
      harness.flow.invalidate();
      harness.preparationRevision++;
      expect(
        (await verification).kind,
        PostEditSubmissionResolutionKind.superseded,
      );
      expect(harness.preparationRevision, 1);
      expect(harness.reads, isEmpty);
    },
  );
  test(
    'attempt freezes attachment IDs and reuses exact intent on form refresh',
    () {
      final added = ['7'];
      final removed = ['9'];
      final attempt = _attempt(added: added, removed: removed);
      added.add('8');
      removed.clear();
      expect(attempt.newImageAttachmentIds, ['7']);
      expect(attempt.removedImageAttachmentIds, ['9']);
      expect(
        () => attempt.newImageAttachmentIds.add('8'),
        throwsUnsupportedError,
      );
      final updated = attempt.withPreparation(
        _preparation(revision: 'refreshed'),
      );
      final submission = updated.toSubmission();
      expect(submission.subject, attempt.subject);
      expect(submission.message, attempt.message);
      expect(submission.useSignature, attempt.useSignature);
      expect(submission.minimumReadAccess, 0);
      expect(submission.newImageAttachmentIds, ['7']);
      expect(submission.removedImageAttachmentIds, ['9']);
    },
  );

  test(
    'applied command preserves read-access evidence without a proof GET',
    () async {
      final harness = _Harness(
        command: (request) => DataCommandApplied(
          ThreadPostEditReceipt(
            target: request.preparation.target,
            publicationState: ThreadPostEditPublicationState.published,
            confirmation: ThreadPostEditConfirmation.serverCallback,
            readAccess: const ThreadReadAccessEvidence(
              kind: ThreadReadAccessEvidenceKind.unverified,
              requested: 0,
            ),
          ),
        ),
      );
      final result = await harness.flow.submit(_attempt())!;
      expect(result.kind, PostEditSubmissionResolutionKind.applied);
      expect(result.readAccess?.requested, 0);
      expect(harness.reads, isEmpty);
      expect(harness.flow.accepts(result.operation), isTrue);
    },
  );

  test('only explicit stale-formhash rejection permits one retry', () async {
    var count = 0;
    final refreshed = _preparation();
    final harness = _Harness(
      command: (request) => count++ == 0
          ? const DataCommandRejected(_staleForm)
          : _applied(request),
      prepare: (_) => _success(refreshed),
    );
    final result = await harness.flow.submit(
      _attempt(added: ['7'], removed: ['9']),
    )!;
    expect(result.kind, PostEditSubmissionResolutionKind.applied);
    expect(harness.commands, hasLength(2));
    expect(harness.reads, hasLength(1));
    expect(harness.commands.last.preparation, same(refreshed));
    expect(harness.commands.last.newImageAttachmentIds, ['7']);
    expect(harness.commands.last.removedImageAttachmentIds, ['9']);
    expect(result.attempt.preparation, same(refreshed));
  });

  test('second formhash rejection never makes a third POST', () async {
    final harness = _Harness(
      command: (_) => const DataCommandRejected(_staleForm),
    );
    final result = await harness.flow.submit(_attempt())!;
    expect(result.kind, PostEditSubmissionResolutionKind.unconfirmed);
    expect(result.detail, 'formhash_retry_exhausted');
    expect(harness.commands, hasLength(2));
    expect(harness.reads, hasLength(1));
  });

  test('changed form revision produces conflict before any resend', () async {
    final changed = _preparation(revision: 'changed');
    final harness = _Harness(
      command: (_) => const DataCommandRejected(_staleForm),
      prepare: (_) => _success(changed),
    );
    final result = await harness.flow.submit(_attempt())!;
    expect(result.kind, PostEditSubmissionResolutionKind.conflict);
    expect(result.snapshot, same(changed));
    expect(harness.commands, hasLength(1));
  });

  test('foreign form target cannot be adopted or retried', () async {
    final foreign = buildPostEditPreparation(
      target: buildPostEditTarget(tid: 'other', isFirstPost: true),
      isFirstPost: true,
    );
    final harness = _Harness(
      command: (_) => const DataCommandRejected(_staleForm),
      prepare: (_) => _success(foreign),
    );
    final result = await harness.flow.submit(_attempt())!;
    expect(result.kind, PostEditSubmissionResolutionKind.unconfirmed);
    expect(result.nativeSupported, isFalse);
    expect(result.snapshot, isNull);
    expect(harness.commands, hasLength(1));
  });

  for (final throwsRead in [false, true]) {
    test('failed form refresh cannot resend (throws: $throwsRead)', () async {
      final harness = _Harness(
        command: (_) => const DataCommandRejected(_staleForm),
        prepare: (_) {
          if (throwsRead) throw StateError('private-payload');
          return _readFailure;
        },
      );
      final result = await harness.flow.submit(_attempt())!;
      expect(result.kind, PostEditSubmissionResolutionKind.unconfirmed);
      expect(result.detail, 'formhash_refresh_failed');
      expect(harness.commands, hasLength(1));
    });
  }

  for (final result in <DataCommandResult<ThreadPostEditReceipt>>[
    const DataCommandRejected(_rejected),
    const DataCommandNotSent(_rejected),
    const DataCommandNotSent(_staleForm),
  ]) {
    test('${result.runtimeType} has no automatic form refresh', () async {
      final harness = _Harness(command: (_) => result);
      final resolved = await harness.flow.submit(_attempt())!;
      expect(resolved.kind, PostEditSubmissionResolutionKind.rejected);
      expect(resolved.failure, isNotNull);
      expect(harness.commands, hasLength(1));
      expect(harness.reads, isEmpty);
    });
  }

  test('unsupported command stays fail-closed', () async {
    final harness = _Harness(command: (_) => const DataCommandUnsupported());
    final result = await harness.flow.submit(_attempt())!;
    expect(result.kind, PostEditSubmissionResolutionKind.unconfirmed);
    expect(result.nativeSupported, isFalse);
    expect(harness.flow.verifyUncertain(), isNull);
  });

  for (final throwsCommand in [false, true]) {
    test(
      'uncertain command only permits explicit readback (throws: $throwsCommand)',
      () async {
        final harness = _Harness(
          command: (_) {
            if (throwsCommand) throw StateError('private-payload');
            return const DataCommandOutcomeUnknown(_unknown);
          },
          prepare: (_) => _success(
            _preparation(
              revision: 'after',
              message: 'submitted',
              permission: 0,
            ),
          ),
        );
        final result = await harness.flow.submit(_attempt())!;
        expect(result.kind, PostEditSubmissionResolutionKind.unconfirmed);
        expect(result.detail, isNot(contains('private-payload')));
        expect(harness.reads, isEmpty);
        expect(harness.flow.submit(_attempt()), isNull);
        final verified = await harness.flow.verifyUncertain()!;
        expect(verified.kind, PostEditSubmissionResolutionKind.applied);
        expect(harness.flow.hasUncertainAttempt, isFalse);
        expect(harness.commands, hasLength(1));
        expect(harness.reads, hasLength(1));
      },
    );
  }

  test(
    'verification coalesces GETs and uses original immutable attachment proof',
    () async {
      final read =
          Completer<
            DataReadResult<
              ThreadPostEditPreparation,
              ThreadPostEditCapabilities
            >
          >();
      final added = ['7'];
      final harness = _Harness(
        command: (_) => const DataCommandOutcomeUnknown(_unknown),
        prepare: (_) => read.future,
      );
      await harness.flow.submit(_attempt(added: added))!;
      added.clear();
      final first = harness.flow.verifyUncertain()!;
      final joined = harness.flow.verifyUncertain()!;
      expect(joined, same(first));
      await pumpEventQueue();
      expect(harness.reads, hasLength(1));
      read.complete(
        _success(
          _preparation(revision: 'after', message: 'submitted', permission: 0),
        ),
      );
      final result = await first;
      expect(result.kind, PostEditSubmissionResolutionKind.partialSuccess);
      expect(harness.flow.hasUncertainAttempt, isTrue);
      expect(harness.commands, hasLength(1));
    },
  );

  test(
    'unknown attachment association remains partial until explicit proof',
    () async {
      final harness = _Harness(
        command: (_) => const DataCommandOutcomeUnknown(
          DataCommandFailure(
            diagnosticMessage: 'test attachment uncertainty',
            kind: DataCommandFailureKind.unknown,
            retryPolicy: DataCommandRetryPolicy.never,
            code: 'post_edit_attachment_state_unconfirmed',
          ),
        ),
      );
      expect(
        (await harness.flow.submit(_attempt())!).kind,
        PostEditSubmissionResolutionKind.partialSuccess,
      );
      expect(harness.flow.hasUncertainAttempt, isTrue);
      expect(harness.reads, isEmpty);
    },
  );

  test(
    'verification distinguishes unchanged baseline and genuine conflict',
    () async {
      var changed = false;
      final harness = _Harness(
        command: (_) => const DataCommandOutcomeUnknown(_unknown),
        prepare: (_) => _success(
          changed
              ? _preparation(revision: 'changed', message: 'other')
              : _preparation(),
        ),
      );
      await harness.flow.submit(_attempt())!;
      final unchanged = await harness.flow.verifyUncertain()!;
      expect(unchanged.kind, PostEditSubmissionResolutionKind.unconfirmed);
      expect(unchanged.detail, 'baseline_unchanged');
      changed = true;
      expect(
        (await harness.flow.verifyUncertain()!).kind,
        PostEditSubmissionResolutionKind.conflict,
      );
      expect(harness.commands, hasLength(1));
    },
  );

  for (final throwsRead in [false, true]) {
    test(
      'verification failure stays recoverable (throws: $throwsRead)',
      () async {
        final harness = _Harness(
          command: (_) => const DataCommandOutcomeUnknown(_unknown),
          prepare: (_) {
            if (throwsRead) throw StateError('private-payload');
            return _readFailure;
          },
        );
        await harness.flow.submit(_attempt())!;
        final result = await harness.flow.verifyUncertain()!;
        expect(result.kind, PostEditSubmissionResolutionKind.unconfirmed);
        expect(result.detail, 'submit_verification_failed');
        expect(harness.flow.hasUncertainAttempt, isTrue);
        expect(harness.flow.isRunning, isFalse);
        expect(harness.commands, hasLength(1));
      },
    );
  }

  test('synchronous port reentrancy cannot start a second command', () async {
    late _Harness harness;
    harness = _Harness(
      command: (request) {
        expect(harness.flow.submit(_attempt()), isNull);
        return _applied(request);
      },
    );
    await harness.flow.submit(_attempt())!;
    expect(harness.commands, hasLength(1));
  });

  for (final close in [false, true]) {
    test(
      'late command cannot publish after invalidation (close: $close)',
      () async {
        final command = Completer<DataCommandResult<ThreadPostEditReceipt>>();
        final harness = _Harness(command: (_) => command.future);
        final request = harness.flow.submit(_attempt())!;
        expect(harness.flow.submit(_attempt()), isNull);
        if (close) {
          harness.flow.close();
        } else {
          harness.flow.invalidate();
        }
        expect(harness.flow.submit(_attempt()), isNull);
        command.complete(const DataCommandOutcomeUnknown(_unknown));
        final result = await request;
        expect(result.kind, PostEditSubmissionResolutionKind.superseded);
        expect(harness.flow.accepts(result.operation), isFalse);
        expect(harness.flow.hasUncertainAttempt, isFalse);
        if (close) expect(harness.flow.submit(_attempt()), isNull);
      },
    );
  }

  test(
    'new shared form read retires formhash retry before any second POST',
    () async {
      final read =
          Completer<
            DataReadResult<
              ThreadPostEditPreparation,
              ThreadPostEditCapabilities
            >
          >();
      final harness = _Harness(
        command: (_) => const DataCommandRejected(_staleForm),
        prepare: (_) => read.future,
      );
      final request = harness.flow.submit(_attempt())!;
      await pumpEventQueue();
      harness.preparationRevision++;
      read.complete(_success(_preparation()));
      expect((await request).kind, PostEditSubmissionResolutionKind.superseded);
      expect(harness.commands, hasLength(1));
    },
  );

  test('local edits and close retire late verification without restoring uncertainty', () async {
    final read =
        Completer<
          DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>
        >();
    final harness = _Harness(
      command: (_) => const DataCommandOutcomeUnknown(_unknown),
      prepare: (_) => read.future,
    );
    await harness.flow.submit(_attempt())!;
    final request = harness.flow.verifyUncertain()!;
    harness.flow.invalidate();
    harness.flow.close();
    read.complete(
      _success(
        _preparation(revision: 'after', message: 'submitted', permission: 0),
      ),
    );
    expect((await request).kind, PostEditSubmissionResolutionKind.superseded);
    expect(harness.flow.verifyUncertain(), isNull);
    expect(harness.commands, hasLength(1));
  });

  test(
    'diagnostic failure cannot turn an unconfirmed write into a thrown flow',
    () async {
      final harness = _Harness(
        command: (_) => const DataCommandRejected(_staleForm),
        prepare: (_) => _readFailure,
        brokenDiagnostics: true,
      );
      expect(
        (await harness.flow.submit(_attempt())!).kind,
        PostEditSubmissionResolutionKind.unconfirmed,
      );
    },
  );
}

const _staleForm = DataCommandFailure(
  diagnosticMessage: 'test form expiry',
  kind: DataCommandFailureKind.staleFormhash,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
);
const _rejected = DataCommandFailure(
  diagnosticMessage: 'test rejection',
  kind: DataCommandFailureKind.permissionDenied,
  retryPolicy: DataCommandRetryPolicy.never,
);
const _unknown = DataCommandFailure(
  diagnosticMessage: 'test uncertainty',
  kind: DataCommandFailureKind.unknown,
  retryPolicy: DataCommandRetryPolicy.never,
  code: 'outcome_unknown',
);
const _readFailure =
    DataReadFailure<ThreadPostEditPreparation, ThreadPostEditCapabilities>(
      kind: DataReadFailureKind.network,
      diagnosticMessage: 'test read failure',
    );

ThreadPostEditPreparation _preparation({
  String revision = 'before',
  String message = 'before',
  int permission = 20,
}) => buildPostEditPreparation(
  isFirstPost: true,
  revision: revision,
  message: message,
  readAccess: ThreadReadAccess(
    canModify: true,
    currentValue: permission,
    options: const [
      ThreadReadAccessOption(value: 0),
      ThreadReadAccessOption(value: 20),
    ],
  ),
);

PostEditSubmissionAttempt _attempt({
  List<String> added = const [],
  List<String> removed = const [],
}) => PostEditSubmissionAttempt(
  preparation: _preparation(),
  subject: '标题',
  message: 'submitted',
  useSignature: true,
  minimumReadAccess: 0,
  newImageAttachmentIds: added,
  removedImageAttachmentIds: removed,
);

DataCommandApplied<ThreadPostEditReceipt> _applied(
  ThreadPostEditSubmission request,
) => DataCommandApplied(
  ThreadPostEditReceipt(
    target: request.preparation.target,
    publicationState: ThreadPostEditPublicationState.published,
    confirmation: ThreadPostEditConfirmation.serverCallback,
  ),
);

DataReadSuccess<ThreadPostEditPreparation, ThreadPostEditCapabilities> _success(
  ThreadPostEditPreparation preparation,
) => DataReadSuccess(
  data: preparation,
  capabilities: buildPostEditCapabilities(),
  metadata: const DataReadMetadata(
    origin: DataReadOrigin.network,
    freshness: DataReadFreshness.current,
  ),
);

class _Harness {
  _Harness({
    FutureOr<DataCommandResult<ThreadPostEditReceipt>> Function(
      ThreadPostEditSubmission,
    )?
    command,
    FutureOr<
      DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>
    >
    Function(ThreadPostEditPreparationRequest)?
    prepare,
    bool brokenDiagnostics = false,
  }) {
    flow = PostEditSubmissionCoordinator(
      executeCommand: _Command((request) {
        commands.add(request);
        return (command ?? _applied)(request);
      }).execute,
      loadPreparation: _Repository((request) {
        reads.add(request);
        return prepare?.call(request) ?? _success(_preparation());
      }).load,
      beginPreparation: () => ++preparationRevision,
      isPreparationCurrent: (request) => request == preparationRevision,
      onDiagnostic: (_, _) {
        if (brokenDiagnostics) throw StateError('diagnostic-failed');
      },
    );
    addTearDown(flow.close);
  }
  late final PostEditSubmissionCoordinator flow;
  final commands = <ThreadPostEditSubmission>[];
  final reads = <ThreadPostEditPreparationRequest>[];
  int preparationRevision = 0;
}

class _Command implements ThreadPostEditCommand {
  _Command(this.handle);
  final FutureOr<DataCommandResult<ThreadPostEditReceipt>> Function(
    ThreadPostEditSubmission,
  )
  handle;
  @override
  ThreadPostEditCapabilities get capabilities => buildPostEditCapabilities();
  @override
  Future<DataCommandResult<ThreadPostEditReceipt>> execute(
    ThreadPostEditSubmission request,
  ) async => handle(request);
}

class _Repository implements ThreadPostEditPreparationRepository {
  _Repository(this.handle);
  final FutureOr<
    DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>
  >
  Function(ThreadPostEditPreparationRequest)
  handle;
  @override
  ThreadPostEditCapabilities get capabilities => buildPostEditCapabilities();
  @override
  Future<DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>>
  load(ThreadPostEditPreparationRequest request) async => handle(request);
}
