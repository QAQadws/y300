part of 'composer_controller_base_test.dart';

void _draftLifecycleCases() {
  test(
    'applied submit with transient local delete failure retries only cleanup on exit',
    () async {
      final repository = _MemoryDraftRepository();
      const args = _TestArgs(fid: '33', tid: '100');
      final container = _buildContainer(draftRepository: repository);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);
      controller.updateMessage('sent input');
      await controller.flushDraft();
      final saves = repository.savedSnapshots.length;
      repository.failNextDelete = true;
      expect((await controller.submit()).sent, isTrue);
      expect(controller.latestState?.message, isEmpty);
      expect(
        (await repository.loadDraft(args.identity))?.message,
        'sent input',
      );
      container.dispose();
      await _drain();
      expect(await repository.loadDraft(args.identity), isNull);
      expect(repository.savedSnapshots, hasLength(saves));
      expect(controller.performSubmitCallCount, 1);
    },
  );
  test(
    'unknown submission preserves the draft and does not retry automatically',
    () async {
      final repository = _MemoryDraftRepository();
      const args = _TestArgs(fid: '33', tid: '100');
      final container = _buildContainer(draftRepository: repository);
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);
      controller.updateMessage('uncertain input');
      controller.outcome = _unknownOutcome;
      final result = await controller.submit();
      await _drain();
      expect(result.sent, isFalse);
      expect(controller.performSubmitCallCount, 1);
      expect(
        (await repository.loadDraft(args.identity))?.message,
        'uncertain input',
      );
      expect(controller.latestState?.message, 'uncertain input');
      expect(
        (result.failure as ComposerSubmissionFailure).code,
        ComposerSubmissionFailureCode.outcomeUnknown,
      );
    },
  );

  for (final applied in [false, true]) {
    test(
      'submit finishing after disposal ${applied ? 'deletes applied input' : 'keeps uncertain input'}',
      () async {
        final repository = _MemoryDraftRepository();
        const args = _TestArgs(fid: '33', tid: '100');
        final container = _buildContainer(draftRepository: repository);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );
        controller.updateMessage('route input');
        await controller.flushDraft();
        final outcome = Completer<ComposerSubmissionOutcome>();
        controller.outcomeFuture = outcome.future;
        final submitting = controller.submit();
        await _drain();
        expect(controller.performSubmitCallCount, 1);
        container.dispose();
        await _drain();
        final savesAfterExit = repository.savedSnapshots.length;
        outcome.complete(
          applied
              ? const ComposerSubmissionOutcome.success(rawDetail: 'ok')
              : _unknownOutcome,
        );
        final result = await submitting;
        await _drain();
        expect(result.sent, applied);
        expect(controller.resetAfterSuccessCallCount, 0);
        expect(repository.savedSnapshots, hasLength(savesAfterExit));
        expect(
          (await repository.loadDraft(args.identity))?.message,
          applied ? isNull : 'route input',
        );
      },
    );
  }

  test(
    'refresh waits for previous final writes before restoring the new session',
    () async {
      final repository = _MemoryDraftRepository();
      const args = _TestArgs(fid: '33', tid: '100');
      final container = _buildContainer(draftRepository: repository);
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);
      final gate = Completer<void>();
      repository.beforeSave = gate.future;
      controller.updateMessage('latest before refresh');
      final writing = controller.flushDraft();
      await _drain();
      final loadsBeforeRefresh = repository.loadCallCount;
      final refreshing = container.refresh(
        _testControllerProvider(args).future,
      );
      await _drain();
      expect(repository.loadCallCount, loadsBeforeRefresh);
      expect(container.read(_testControllerProvider(args)).isLoading, isTrue);
      gate.complete();
      await writing;
      final refreshed = await refreshing;
      expect(refreshed.message, 'latest before refresh');
      expect(repository.loadCallCount, loadsBeforeRefresh + 1);
    },
  );

  test(
    'verification from an older build cannot replace refreshed input',
    () async {
      final repository = _MemoryDraftRepository();
      const args = _TestArgs(fid: '33', tid: '100');
      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: args.identity,
          message: 'stored',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 10, 4),
        ),
      );
      final verification = _DeferredInitialVerification();
      final container = _buildContainer(
        draftRepository: repository,
        verificationService: verification,
      );
      addTearDown(container.dispose);
      _keepAlive(container, args);
      final initial = container
          .read(_testControllerProvider(args).future)
          .then<Object?>(
            (value) => value,
            onError: (Object error, StackTrace _) => error,
          );
      await _drain();
      expect(verification.calls, 1);
      await container.refresh(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);
      controller.updateMessage('new session input');
      await controller.flushDraft();
      final builds = controller.afterBuildCallCount;
      verification.completeOld();
      await initial;
      await _drain();
      expect(controller.afterBuildCallCount, builds);
      expect(controller.latestState?.message, 'new session input');
      expect(
        (await repository.loadDraft(args.identity))?.message,
        'new session input',
      );
    },
  );

  test('applied cleanup in flight cannot reset a refreshed session', () async {
    final repository = _MemoryDraftRepository();
    const args = _TestArgs(fid: '33', tid: '100');
    final container = _buildContainer(draftRepository: repository);
    addTearDown(container.dispose);
    _keepAlive(container, args);
    await container.read(_testControllerProvider(args).future);
    final oldController = container.read(
      _testControllerProvider(args).notifier,
    );
    oldController.updateMessage('sent input');
    await oldController.flushDraft();
    final deletion = Completer<void>();
    repository.beforeDelete = deletion.future;
    final submitting = oldController.submit();
    await _drain();
    final refreshing = container.refresh(_testControllerProvider(args).future);
    await _drain();
    deletion.complete();
    expect((await submitting).sent, isTrue);
    await refreshing;
    expect(oldController.resetAfterSuccessCallCount, 0);
    final controller = container.read(_testControllerProvider(args).notifier);
    controller.updateMessage('input after refresh');
    await controller.flushDraft();
    expect(controller.latestState?.message, 'input after refresh');
    expect(
      (await repository.loadDraft(args.identity))?.message,
      'input after refresh',
    );
  });
}

const _unknownOutcome = ComposerSubmissionOutcome.failure(
  failure: ComposerSubmissionFailure(
    code: ComposerSubmissionFailureCode.outcomeUnknown,
    kind: ComposerKind.reply,
  ),
);

final class _DeferredInitialVerification
    implements ComposerDraftAttachmentVerificationService {
  int calls = 0;
  ComposerDraftSnapshot? _old;
  final _gate = Completer<ComposerDraftAttachmentVerificationResult>();

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) {
    calls += 1;
    if (calls == 1) {
      _old = draft;
      return _gate.future;
    }
    return Future.value(
      ComposerDraftAttachmentVerificationResult(
        draft: draft,
        verification: const ComposerDraftAttachmentVerification.notRequired(),
      ),
    );
  }

  void completeOld() {
    final old = _old!;
    _gate.complete(
      ComposerDraftAttachmentVerificationResult(
        draft: ComposerDraftSnapshot(
          identity: old.identity,
          message: 'late verified input',
          useSignature: old.useSignature,
          updatedAt: old.updatedAt,
        ),
        verification: ComposerDraftAttachmentVerification.verified(
          imagesByAid: const {},
          invalidAidCount: 0,
          checkedAids: const {},
        ),
      ),
    );
  }
}
