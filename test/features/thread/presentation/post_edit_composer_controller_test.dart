import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
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

  test(
    'uses the edit identity and keeps a clean baseline out of drafts',
    () async {
      final controller = PostEditComposerController(
        PostEditComposerArgs(preparation: preparation),
      );
      final state = await controller.buildInitialState(
        restoredDraft: null,
        preferences: ComposerPreferences.defaults(),
      );

      expect(controller.composerKind, ComposerKind.postEdit);
      expect(controller.draftIdentity.storageKey, 'edit:5:557857:41587383');
      expect(state.message, snapshot.rawMessage);
      expect(state.isDirtyAgainstBaseline, isFalse);
      expect(controller.shouldPersistDraft(state), isFalse);
    },
  );

  test('restores a draft only when its baseline fingerprint matches', () async {
    final controller = PostEditComposerController(
      PostEditComposerArgs(preparation: preparation),
    );
    final draft = ComposerDraftSnapshot(
      identity: controller.draftIdentity,
      message: '本地修改',
      useSignature: false,
      updatedAt: DateTime.utc(2026, 8, 1),
      extras: const <String, String>{'baselineFingerprint': 'fp-1'},
    );

    final restored = await controller.buildInitialState(
      restoredDraft: draft,
      preferences: ComposerPreferences.defaults(),
    );
    expect(restored.message, '本地修改');
    expect(restored.restoredDraft, isTrue);
    expect(restored.pendingConflict, isNull);

    final conflict = await controller.buildInitialState(
      restoredDraft: draft.copyWithForTest(
        extras: const <String, String>{'baselineFingerprint': 'old-fp'},
      ),
      preferences: ComposerPreferences.defaults(),
    );
    expect(conflict.message, snapshot.rawMessage);
    expect(conflict.restoredDraft, isFalse);
    expect(conflict.pendingConflict, isNotNull);
    expect(controller.shouldPersistDraft(conflict), isTrue);
    expect(controller.draftSnapshotFor(conflict).message, '本地修改');
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
    successfulControls: const <PostEditFormField>[],
    existingImages: const <PostEditExistingImage>[],
    structureEvidence: PostEditFormStructureEvidence(
      allNamedControlNamesInDomOrder: const <String>[],
    ),
    baselineFingerprint: 'fp-1',
  );
}

extension on ComposerDraftSnapshot {
  ComposerDraftSnapshot copyWithForTest({Map<String, String>? extras}) {
    return ComposerDraftSnapshot(
      identity: identity,
      message: message,
      useSignature: useSignature,
      updatedAt: updatedAt,
      subject: subject,
      extras: extras ?? this.extras,
      imageAttachments: imageAttachments,
    );
  }
}
