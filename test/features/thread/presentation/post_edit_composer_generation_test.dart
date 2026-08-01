import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/thread/data/providers/post_edit_providers.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/repositories/post_edit_repository.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_controller.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';

void main() {
  test(
    'drops an older WebView readback after a newer readback completes',
    () async {
      final repository = _DelayedPostEditRepository();
      final args = _args(_snapshot(message: 'server-1', fingerprint: 'fp-1'));
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
        ApiSuccess(
          _preparation(_snapshot(message: 'server-2', fingerprint: 'fp-2')),
        ),
      );
      await newer;
      repository.completeLoad(
        0,
        ApiSuccess(
          _preparation(_snapshot(message: 'stale-server', fingerprint: 'fp-3')),
        ),
      );
      await older;

      final state = container
          .read(postEditComposerControllerProvider(args))
          .value!;
      expect(state.snapshot.baselineFingerprint, 'fp-2');
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
      final repository = _DelayedPostEditRepository();
      final args = _args(
        _snapshot(
          message: 'server',
          fingerprint: 'fp-1',
          images: <PostEditExistingImage>[
            PostEditExistingImage(
              aid: '1',
              imageUri: Uri.parse('https://bbs.yamibo.com/1.jpg'),
              isAssociated: true,
            ),
            PostEditExistingImage(
              aid: '2',
              imageUri: Uri.parse('https://bbs.yamibo.com/2.jpg'),
              isAssociated: true,
            ),
          ],
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
        ApiSuccess(
          _preparation(
            _snapshot(
              message: 'server',
              fingerprint: 'fp-2',
              images: <PostEditExistingImage>[
                PostEditExistingImage(
                  aid: '1',
                  imageUri: Uri.parse('https://bbs.yamibo.com/1.jpg'),
                  isAssociated: true,
                ),
              ],
            ),
          ),
        ),
      );
      repository.completeLoad(
        0,
        ApiSuccess(
          _preparation(
            _snapshot(
              message: 'server',
              fingerprint: 'fp-3',
              images: <PostEditExistingImage>[
                PostEditExistingImage(
                  aid: '2',
                  imageUri: Uri.parse('https://bbs.yamibo.com/2.jpg'),
                  isAssociated: true,
                ),
              ],
            ),
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
      expect(state.message, 'server');
    },
  );
}

ProviderContainer _buildContainer(_DelayedPostEditRepository repository) {
  return ProviderContainer(
    overrides: [
      postEditRepositoryProvider.overrideWithValue(repository),
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
) {
  return container.listen<AsyncValue<PostEditComposerState>>(
    postEditComposerControllerProvider(args),
    (_, _) {},
  );
}

Future<void> _drain({int rounds = 6}) async {
  for (var index = 0; index < rounds; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

PostEditComposerArgs _args(PostEditFormSnapshot snapshot) {
  return PostEditComposerArgs(preparation: _preparation(snapshot));
}

PostEditPreparation _preparation(PostEditFormSnapshot snapshot) {
  return PostEditPreparation(
    target: snapshot.target,
    decision: const PostEditNativeSupported(profileVersion: 1),
    snapshot: snapshot,
  );
}

PostEditFormSnapshot _snapshot({
  required String message,
  required String fingerprint,
  List<PostEditExistingImage> images = const <PostEditExistingImage>[],
}) {
  final target = PostEditTarget(
    editUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=557857&pid=41587383',
    ),
    fid: '5',
    tid: '557857',
    pid: '41587383',
    page: 1,
    isFirstPost: false,
  );
  return PostEditFormSnapshot(
    target: target,
    sourceUri: target.editUri,
    submitUri: target.editUri,
    formHash: 'formhash-not-logged',
    postTime: '1700000000',
    rawMessage: message,
    originalSubject: 'subject-not-used',
    successfulControls: [
      PostEditFormField(
        name: 'message',
        value: message,
        controlKind: PostEditFormControlKind.textarea,
      ),
    ],
    existingImages: images,
    structureEvidence: PostEditFormStructureEvidence(
      allNamedControlNamesInDomOrder: const <String>['message'],
    ),
    baselineFingerprint: fingerprint,
  );
}

class _DelayedPostEditRepository implements PostEditRepository {
  final List<Completer<ApiResult<PostEditPreparation>>> loadRequests =
      <Completer<ApiResult<PostEditPreparation>>>[];

  @override
  Future<ApiResult<PostEditPreparation>> loadForm(PostEditTarget target) {
    final request = Completer<ApiResult<PostEditPreparation>>();
    loadRequests.add(request);
    return request.future;
  }

  void completeLoad(int index, ApiResult<PostEditPreparation> result) {
    loadRequests[index].complete(result);
  }

  @override
  Future<ApiResult<PostEditAttachmentDeleteResult>> deleteImage(
    PostEditAttachmentDeleteCommand command,
  ) async {
    return ApiSuccess(
      PostEditAttachmentDeleteResult(
        aid: command.aid,
        outcome: PostEditAttachmentDeleteOutcome.deleted,
        deletedCount: 1,
      ),
    );
  }

  @override
  Future<ApiResult<PostEditSubmitResponse>> submit(
    PostEditSubmitPayload payload, {
    required PostEditTarget target,
  }) async {
    return const ApiFailure(
      ApiError(type: ApiErrorType.network, message: 'test-only'),
    );
  }
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
  Future<List<ComposerPickedImage>> pickImagesInOrder() async {
    return const <ComposerPickedImage>[];
  }
}

class _NoopUploadCoordinator implements ComposerImageUploadCoordinator {
  @override
  void cancel() {}

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) {
    return const Stream<ComposerImageUploadEvent>.empty();
  }
}
