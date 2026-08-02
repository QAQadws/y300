import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_submit_verification_service.dart';

void main() {
  const service = PostEditSubmitVerificationService();
  final before = _snapshot(message: 'old', fingerprint: 'before');

  test('keeps an unchanged baseline unconfirmed', () {
    final result = service.verify(
      before: before,
      after: before,
      submittedSubject: 'subject',
      submittedMessage: 'new',
      attachNewAids: const [],
    );

    expect(result.kind, PostEditSubmitResponseKind.ambiguous);
  });

  test('confirms equivalent message and associated new aids', () {
    final result = service.verify(
      before: before,
      after: _snapshot(
        message: 'new\n[attach]123[/attach]',
        fingerprint: 'after',
        aids: const ['123'],
      ),
      submittedSubject: ' subject ',
      submittedMessage: 'new\r\n[attachimg]123[/attachimg]',
      attachNewAids: const ['123'],
    );

    expect(result.kind, PostEditSubmitResponseKind.confirmedSuccess);
  });

  test('reports partial success when a new aid is not associated', () {
    final result = service.verify(
      before: before,
      after: _snapshot(message: 'new', fingerprint: 'after'),
      submittedSubject: 'subject',
      submittedMessage: 'new',
      attachNewAids: const ['123'],
    );

    expect(result.kind, PostEditSubmitResponseKind.partialSuccess);
  });

  test('reports a conflict when the server message differs', () {
    final result = service.verify(
      before: before,
      after: _snapshot(message: 'someone else', fingerprint: 'after'),
      submittedSubject: 'subject',
      submittedMessage: 'new',
      attachNewAids: const [],
    );

    expect(result.kind, PostEditSubmitResponseKind.ambiguous);
    expect(result.snapshot, isNotNull);
  });

  test('reports a conflict when the server subject differs', () {
    final result = service.verify(
      before: before,
      after: _snapshot(
        message: 'new',
        fingerprint: 'after',
        originalSubject: 'server title',
      ),
      submittedSubject: 'local title',
      submittedMessage: 'new',
      attachNewAids: const [],
    );

    expect(result.kind, PostEditSubmitResponseKind.ambiguous);
    expect(result.detail, 'subject_mismatch');
    expect(result.snapshot, isNotNull);
  });
}

PostEditFormSnapshot _snapshot({
  required String message,
  required String fingerprint,
  String originalSubject = 'subject',
  List<String> aids = const [],
}) {
  final target = PostEditTarget(
    editUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&tid=20&pid=30',
    ),
    fid: '5',
    tid: '20',
    pid: '30',
    page: 1,
    isFirstPost: false,
  );
  return PostEditFormSnapshot(
    target: target,
    sourceUri: target.editUri,
    submitUri: target.editUri,
    formHash: 'hash',
    postTime: 'post-time',
    rawMessage: message,
    originalSubject: originalSubject,
    successfulControls: [
      PostEditFormField(
        name: 'message',
        value: message,
        controlKind: PostEditFormControlKind.textarea,
      ),
    ],
    existingImages: [
      for (final aid in aids)
        PostEditExistingImage(
          aid: aid,
          imageUri: Uri.parse('https://bbs.yamibo.com/$aid.jpg'),
          isAssociated: true,
        ),
    ],
    structureEvidence: PostEditFormStructureEvidence(
      allNamedControlNamesInDomOrder: const ['message'],
    ),
    baselineFingerprint: fingerprint,
  );
}
