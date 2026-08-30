import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_submit_verification_service.dart';

import '../../test_support/post_edit_test_support.dart';

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
    expect(result.detail, 'message_mismatch');
  });

  test('reports a conflict when the server subject differs', () {
    final result = service.verify(
      before: before,
      after: _snapshot(
        message: 'new',
        fingerprint: 'after',
        subject: 'server title',
      ),
      submittedSubject: 'local title',
      submittedMessage: 'new',
      attachNewAids: const [],
    );

    expect(result.kind, PostEditSubmitResponseKind.ambiguous);
    expect(result.detail, 'subject_mismatch');
  });
}

ThreadPostEditPreparation _snapshot({
  required String message,
  required String fingerprint,
  String subject = 'subject',
  List<String> aids = const [],
}) {
  final target = buildPostEditTarget(
    fid: '5',
    tid: '20',
    pid: '30',
    isFirstPost: true,
  );
  return buildPostEditPreparation(
    target: target,
    isFirstPost: true,
    subject: subject,
    message: message,
    revision: fingerprint,
    existingImages: [
      for (final aid in aids)
        ThreadPostEditImageAttachment(
          aid: aid,
          imageUri: Uri.parse('https://bbs.yamibo.com/$aid.jpg'),
          isAssociated: true,
        ),
    ],
  );
}
