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

ProviderContainer _buildContainer(_DelayedPreparationRepository repository) {
  return ProviderContainer(
    overrides: [
      threadPostEditPreparationRepositoryProvider.overrideWithValue(repository),
      threadPostEditCommandProvider.overrideWithValue(
        const _UnusedEditCommand(),
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
