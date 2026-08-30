import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_controller.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';

import '../test_support/post_edit_test_support.dart';

void main() {
  final target = buildPostEditTarget();
  final preparation = buildPostEditPreparation(target: target);

  test('starts every edit session from the current server message', () async {
    final controller = PostEditComposerController(
      PostEditComposerArgs(target: target, preparation: preparation),
    );
    final state = await controller.buildInitialState(
      restoredDraft: null,
      preferences: ComposerPreferences.defaults(),
    );

    expect(controller.composerKind, ComposerKind.postEdit);
    expect(controller.draftsEnabled, isFalse);
    expect(controller.draftIdentity, isNull);
    expect(state.message, preparation.message);
    expect(state.subject, preparation.subject);
    expect(state.isDirtyAgainstBaseline, isFalse);
    expect(controller.shouldPersistDraft(state), isFalse);
  });

  test('does not expose an edit draft snapshot', () async {
    final controller = PostEditComposerController(
      PostEditComposerArgs(target: target, preparation: preparation),
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
      target: target,
      snapshot: preparation,
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
  });

  test('tracks a first-post subject against the server baseline', () async {
    final firstPostTarget = buildPostEditTarget(isFirstPost: true);
    final firstPostPreparation = buildPostEditPreparation(
      target: firstPostTarget,
      isFirstPost: true,
    );
    final controller = PostEditComposerController(
      PostEditComposerArgs(
        target: firstPostTarget,
        preparation: firstPostPreparation,
      ),
    );
    final state = await controller.buildInitialState(
      restoredDraft: null,
      preferences: ComposerPreferences.defaults(),
    );

    expect(state.subject, firstPostPreparation.subject);
    expect(state.isDirtyAgainstBaseline, isFalse);
    expect(state.copyWith(subject: '新的标题').isDirtyAgainstBaseline, isTrue);
  });
}
