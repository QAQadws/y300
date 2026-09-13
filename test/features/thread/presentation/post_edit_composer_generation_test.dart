import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/thread/data/providers/post_edit_providers.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_controller.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';

import '../test_support/post_edit_test_support.dart';

void main() {
  test(
    'formhash refresh detects a permission-only server conflict before retrying',
    () async {
      final target = buildPostEditTarget(isFirstPost: true);
      ThreadPostEditPreparation prepared(int permission, String revision) =>
          buildPostEditPreparation(
            target: target,
            isFirstPost: true,
            revision: revision,
            readAccess: ThreadReadAccess(
              canModify: true,
              currentValue: permission,
              options: const [
                ThreadReadAccessOption(value: 0),
                ThreadReadAccessOption(value: 20),
              ],
            ),
          );
      final args = PostEditComposerArgs(
        target: target,
        preparation: prepared(20, 'before'),
      );
      final repository = _DelayedPreparationRepository();
      final command = _IndeterminateEditCommand(staleFormhash: true);
      final container = _buildContainer(repository, command: command);
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postEditComposerControllerProvider(args).future);
      final controller = container.read(
        postEditComposerControllerProvider(args).notifier,
      );
      controller.updateMessage('local body');
      final submit = controller.submit();
      await _drain();
      repository.completeLoad(0, _success(prepared(0, 'changed')));
      expect((await submit).sent, isFalse);
      final state = container
          .read(postEditComposerControllerProvider(args))
          .value!;
      expect(state.pendingConflict, isNotNull);
      expect(state.pendingConflict!.localMinimumReadAccess, 20);
      expect(state.snapshot.readAccess.currentValue, 0);
      expect(command.calls, 1);
    },
  );

  test(
    'unknown edit result permits verification but never a second POST',
    () async {
      final target = buildPostEditTarget(isFirstPost: true);
      final before = buildPostEditPreparation(
        target: target,
        isFirstPost: true,
        readAccess: const ThreadReadAccess(
          canModify: true,
          currentValue: 20,
          options: [ThreadReadAccessOption(value: 0)],
        ),
      );
      final args = PostEditComposerArgs(target: target, preparation: before);
      final repository = _DelayedPreparationRepository();
      final command = _IndeterminateEditCommand();
      final container = _buildContainer(repository, command: command);
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postEditComposerControllerProvider(args).future);
      final controller = container.read(
        postEditComposerControllerProvider(args).notifier,
      );
      controller.updateMinimumReadAccess(0);
      expect((await controller.submit()).sent, isFalse);
      expect((await controller.submit()).sent, isFalse);
      expect(command.calls, 1);
      final verification = controller.retrySubmitVerification();
      await _drain();
      repository.completeLoad(
        0,
        _success(
          buildPostEditPreparation(
            target: target,
            isFirstPost: true,
            revision: 'after',
            readAccess: const ThreadReadAccess(
              canModify: true,
              currentValue: 0,
              options: [ThreadReadAccessOption(value: 0)],
            ),
          ),
        ),
      );
      await verification;
      expect(
        container
            .read(postEditComposerControllerProvider(args))
            .value!
            .submitBlocked,
        isFalse,
      );
      expect(command.calls, 1);
    },
  );

  test(
    'permission conflicts preserve local choice or adopt the server selection',
    () async {
      final target = buildPostEditTarget(isFirstPost: true);
      ThreadPostEditPreparation prepared(int permission, String revision) =>
          buildPostEditPreparation(
            target: target,
            isFirstPost: true,
            revision: revision,
            readAccess: ThreadReadAccess(
              canModify: true,
              currentValue: permission,
              options: const [
                ThreadReadAccessOption(value: 0),
                ThreadReadAccessOption(value: 20),
                ThreadReadAccessOption(value: 40),
              ],
            ),
          );
      final repository = _DelayedPreparationRepository();
      final args = PostEditComposerArgs(
        target: target,
        preparation: prepared(20, 'before'),
      );
      final container = _buildContainer(repository);
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postEditComposerControllerProvider(args).future);
      final controller = container.read(
        postEditComposerControllerProvider(args).notifier,
      );
      controller.updateMinimumReadAccess(0);
      expect(
        container
            .read(postEditComposerControllerProvider(args))
            .value!
            .canSubmit,
        isTrue,
      );
      final reconcile = controller.reconcileWebViewReturn();
      await _drain();
      repository.completeLoad(0, _success(prepared(40, 'changed')));
      await reconcile;
      expect(
        container
            .read(postEditComposerControllerProvider(args))
            .value!
            .pendingConflict!
            .localMinimumReadAccess,
        0,
      );
      await controller.keepLocalVersion();
      expect(
        container
            .read(postEditComposerControllerProvider(args))
            .value!
            .minimumReadAccess,
        0,
      );
      expect(
        container
            .read(postEditComposerControllerProvider(args))
            .value!
            .snapshot
            .readAccess
            .currentValue,
        40,
      );
      final again = controller.reconcileWebViewReturn();
      await _drain();
      repository.completeLoad(1, _success(prepared(20, 'changed-again')));
      await again;
      await controller.useServerVersion();
      final state = container
          .read(postEditComposerControllerProvider(args))
          .value!;
      expect(state.minimumReadAccess, 20);
      expect(state.isDirtyAgainstBaseline, isFalse);
    },
  );

  test(
    'drops an older WebView readback after a newer readback completes',
    () async {
      final repository = _DelayedPreparationRepository();
      final args = _args(_preparation(message: 'server-1', revision: 'fp-1'));
      final container = _buildContainer(repository);
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      await container.read(postEditComposerControllerProvider(args).future);
      final controller = container.read(
        postEditComposerControllerProvider(args).notifier,
      );

      final older = controller.reconcileWebViewReturn();
      final newer = controller.reconcileWebViewReturn();
      await _drain();
      expect(repository.loadRequests, hasLength(2));

      repository.completeLoad(
        1,
        _success(_preparation(message: 'server-2', revision: 'fp-2')),
      );
      await newer;
      repository.completeLoad(
        0,
        _success(_preparation(message: 'stale-server', revision: 'fp-3')),
      );
      await older;

      final state = container
          .read(postEditComposerControllerProvider(args))
          .value!;
      expect(state.snapshot.revision, 'fp-2');
      expect(state.message, 'server-2');
      expect(
        state.webReturnVerificationState,
        PostEditWebReturnVerificationState.changedClean,
      );
    },
  );

  test(
    'keeps independent delete generations from polluting each other',
    () async {
      final repository = _DelayedPreparationRepository();
      final args = _args(
        _preparation(
          message: 'server',
          revision: 'fp-1',
          images: [_image('1'), _image('2')],
        ),
      );
      final container = _buildContainer(repository);
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      await container.read(postEditComposerControllerProvider(args).future);
      final controller = container.read(
        postEditComposerControllerProvider(args).notifier,
      );
      final first = controller.deleteImage('1');
      final second = controller.deleteImage('2');
      await _drain();
      expect(repository.loadRequests, hasLength(2));

      repository.completeLoad(
        1,
        _success(
          _preparation(
            message: 'server',
            revision: 'fp-2',
            images: [_image('1')],
          ),
        ),
      );
      repository.completeLoad(
        0,
        _success(
          _preparation(
            message: 'server',
            revision: 'fp-3',
            images: [_image('2')],
          ),
        ),
      );
      await Future.wait([first, second]);

      final state = container
          .read(postEditComposerControllerProvider(args))
          .value!;
      expect(
        state.attachmentSession.deletedAidTombstones,
        containsAll(['1', '2']),
      );
      expect(state.attachmentSession.existingImagesByAid, isEmpty);
      expect(state.attachmentSession.deletingAids, isEmpty);
    },
  );
}

ProviderContainer _buildContainer(
  _DelayedPreparationRepository repository, {
  ThreadPostEditCommand? command,
}) {
  return ProviderContainer(
    overrides: [
      threadPostEditPreparationRepositoryProvider.overrideWithValue(repository),
      threadPostEditCommandProvider.overrideWithValue(
        command ?? const _UnusedEditCommand(),
      ),
      postEditImageAttachmentDeleteCommandProvider.overrideWithValue(
        const _AppliedAttachmentDeleteCommand(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        _MemoryComposerPreferencesRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(_NoopImagePicker()),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        _NoopUploadCoordinator(),
      ),
    ],
  );
}

ProviderSubscription<AsyncValue<PostEditComposerState>> _keepAlive(
  ProviderContainer container,
  PostEditComposerArgs args,
) => container.listen(postEditComposerControllerProvider(args), (_, _) {});

Future<void> _drain({int rounds = 6}) async {
  for (var index = 0; index < rounds; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

PostEditComposerArgs _args(ThreadPostEditPreparation preparation) {
  final target = buildPostEditTarget();
  return PostEditComposerArgs(target: target, preparation: preparation);
}

ThreadPostEditPreparation _preparation({
  required String message,
  required String revision,
  List<ThreadPostEditImageAttachment> images =
      const <ThreadPostEditImageAttachment>[],
}) => buildPostEditPreparation(
  target: buildPostEditTarget(),
  message: message,
  revision: revision,
  existingImages: images,
);

ThreadPostEditImageAttachment _image(String aid) =>
    ThreadPostEditImageAttachment(
      aid: aid,
      imageUri: Uri.parse('https://bbs.yamibo.com/$aid.jpg'),
      isAssociated: true,
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

class _DelayedPreparationRepository
    implements ThreadPostEditPreparationRepository {
  final List<
    Completer<
      DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>
    >
  >
  loadRequests = [];

  @override
  ThreadPostEditCapabilities get capabilities => buildPostEditCapabilities();

  @override
  Future<DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>>
  load(ThreadPostEditPreparationRequest request) {
    final completer =
        Completer<
          DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>
        >();
    loadRequests.add(completer);
    return completer.future;
  }

  void completeLoad(
    int index,
    DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>
    result,
  ) => loadRequests[index].complete(result);
}

class _AppliedAttachmentDeleteCommand
    implements ForumPostImageAttachmentDeleteCommand {
  const _AppliedAttachmentDeleteCommand();

  @override
  Future<DataCommandResult<ForumImageAttachmentDeleteReceipt>> execute(
    DeletePostImageAttachmentRequest request,
  ) async => DataCommandApplied(
    ForumImageAttachmentDeleteReceipt(aid: request.aid, deletedCount: 1),
  );
}

class _UnusedEditCommand implements ThreadPostEditCommand {
  const _UnusedEditCommand();

  @override
  ThreadPostEditCapabilities get capabilities => buildPostEditCapabilities();

  @override
  Future<DataCommandResult<ThreadPostEditReceipt>> execute(
    ThreadPostEditSubmission submission,
  ) async => const DataCommandUnsupported();
}

class _MemoryComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  @override
  Future<ComposerPreferences> load() async => ComposerPreferences.defaults();

  @override
  Future<void> save(ComposerPreferences preferences) async {}
}

class _NoopImagePicker implements ComposerImagePicker {
  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async => const [];
}

class _NoopUploadCoordinator implements ComposerImageUploadCoordinator {
  @override
  void cancel() {}

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) => const Stream.empty();
}

class _IndeterminateEditCommand implements ThreadPostEditCommand {
  _IndeterminateEditCommand({this.staleFormhash = false});
  final bool staleFormhash;
  int calls = 0;
  @override
  ThreadPostEditCapabilities get capabilities => buildPostEditCapabilities();
  @override
  Future<DataCommandResult<ThreadPostEditReceipt>> execute(
    ThreadPostEditSubmission submission,
  ) async {
    calls++;
    if (staleFormhash) {
      return const DataCommandRejected(
        DataCommandFailure(
          kind: DataCommandFailureKind.staleFormhash,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'submit_invalid',
          diagnosticMessage: 'submit_invalid',
        ),
      );
    }
    return const DataCommandOutcomeUnknown(
      DataCommandFailure(
        kind: DataCommandFailureKind.unknown,
        retryPolicy: DataCommandRetryPolicy.never,
        code: 'unknown',
        diagnosticMessage: 'unknown',
      ),
    );
  }
}
