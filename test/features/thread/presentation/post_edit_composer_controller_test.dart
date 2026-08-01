import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_controller.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';

void main() {
  final snapshot = _snapshot();
  final preparation = PostEditPreparation(
    target: snapshot.target,
    decision: const PostEditNativeSupported(profileVersion: 1),
    snapshot: snapshot,
  );

  test('starts every edit session from the current server message', () async {
    final controller = PostEditComposerController(
      PostEditComposerArgs(preparation: preparation),
    );
    final state = await controller.buildInitialState(
      restoredDraft: null,
      preferences: ComposerPreferences.defaults(),
    );

    expect(controller.composerKind, ComposerKind.postEdit);
    expect(controller.draftsEnabled, isFalse);
    expect(controller.draftIdentity, isNull);
    expect(state.message, snapshot.rawMessage);
    expect(state.isDirtyAgainstBaseline, isFalse);
    expect(controller.shouldPersistDraft(state), isFalse);
  });

  test('does not expose an edit draft snapshot', () async {
    final controller = PostEditComposerController(
      PostEditComposerArgs(preparation: preparation),
    );
    final state = await controller.buildInitialState(
      restoredDraft: null,
      preferences: ComposerPreferences.defaults(),
    );

    expect(
      () => controller.draftSnapshotFor(state),
      throwsA(isA<StateError>()),
    );
  });

  test('only remote-capable work requires a defensive refresh on exit', () {
    final initial = PostEditComposerState.initial(
      target: snapshot.target,
      snapshot: snapshot,
    );

    expect(initial.mayHaveServerMutationOnExit, isFalse);
    expect(
      initial.copyWith(message: '仅本地修改').mayHaveServerMutationOnExit,
      isFalse,
    );
    expect(
      initial.copyWith(isUploadingImages: true).mayHaveServerMutationOnExit,
      isTrue,
    );
    expect(
      initial
          .copyWith(submitState: PostEditSubmitState.unconfirmed)
          .mayHaveServerMutationOnExit,
      isTrue,
    );
    expect(
      initial
          .copyWith(serverMutationPossible: true)
          .mayHaveServerMutationOnExit,
      isTrue,
    );
    expect(
      initial
          .copyWith(
            webReturnVerificationState:
                PostEditWebReturnVerificationState.conflict,
          )
          .mayHaveServerMutationOnExit,
      isTrue,
    );
  });
}

PostEditFormSnapshot _snapshot() {
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
    formHash: 'not-persisted',
    postTime: '1700000000',
    rawMessage: '服务器正文',
    originalSubject: '标题',
    successfulControls: const <PostEditFormField>[
      PostEditFormField(
        name: 'message',
        value: '服务器正文',
        controlKind: PostEditFormControlKind.textarea,
      ),
    ],
    existingImages: const <PostEditExistingImage>[],
    structureEvidence: PostEditFormStructureEvidence(
      allNamedControlNamesInDomOrder: const <String>['message'],
    ),
    baselineFingerprint: 'fp-1',
  );
}
