import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_submit_payload_builder.dart';

void main() {
  test('keeps ordered duplicate fields and appends referenced new aids', () {
    final snapshot = _snapshot(
      controls: const [
        PostEditFormField(
          name: 'formhash',
          value: 'hash',
          controlKind: PostEditFormControlKind.hidden,
        ),
        PostEditFormField(
          name: 'subject',
          value: '标题',
          controlKind: PostEditFormControlKind.text,
        ),
        PostEditFormField(
          name: 'fid',
          value: '5',
          controlKind: PostEditFormControlKind.hidden,
        ),
        PostEditFormField(
          name: 'tid',
          value: '20',
          controlKind: PostEditFormControlKind.hidden,
        ),
        PostEditFormField(
          name: 'pid',
          value: '30',
          controlKind: PostEditFormControlKind.hidden,
        ),
        PostEditFormField(
          name: 'tags',
          value: 'a',
          controlKind: PostEditFormControlKind.text,
        ),
        PostEditFormField(
          name: 'tags',
          value: 'b',
          controlKind: PostEditFormControlKind.text,
        ),
        PostEditFormField(
          name: 'message',
          value: '服务器正文',
          controlKind: PostEditFormControlKind.textarea,
        ),
        PostEditFormField(
          name: 'editsubmit',
          value: 'no',
          controlKind: PostEditFormControlKind.hidden,
        ),
      ],
    );
    final payload = const PostEditSubmitPayloadBuilder().build(
      PostEditSubmitCommand(
        target: snapshot.target,
        snapshot: snapshot,
        message:
            '[attachimg]123[/attachimg] [attach]123[/attach] [attach]9[/attach] [attach]777[/attach]',
        imageAttachments: [
          ComposerImageAttachment(
            localId: 'upload-1',
            localPath: '/tmp/one.jpg',
            fileName: 'one.jpg',
            mimeType: 'image/jpeg',
            order: 0,
            status: ComposerImageAttachmentStatus.uploaded,
            aid: '123',
            uploadedAt: DateTime(2026, 8, 1),
          ),
        ],
        attachmentSession: PostEditAttachmentSession.fromImages([
          PostEditExistingImage(
            aid: '9',
            imageUri: Uri.parse('https://bbs.yamibo.com/9.jpg'),
            isAssociated: true,
          ),
        ]),
        now: DateTime(2026, 8, 1, 1),
      ),
    );

    expect(payload.fields.map((entry) => '${entry.key}=${entry.value}'), [
      'formhash=hash',
      'subject=标题',
      'fid=5',
      'tid=20',
      'pid=30',
      'tags=a',
      'tags=b',
      'message=[attachimg]123[/attachimg] [attach]123[/attach] [attach]9[/attach] [attach]777[/attach]',
      'editsubmit=yes',
      'attachnew[123][description]=',
    ]);
    expect(payload.attachNewAids, ['123']);
    expect(payload.danglingAids, ['777']);
    expect(payload.submitUri.queryParameters['formhash'], isNull);
    expect(payload.submitUri.queryParameters['handlekey'], 'postform');
    expect(payload.submitUri.queryParameters['inajax'], '1');
  });

  test('filters destructive and tombstoned attachment fields', () {
    final snapshot = _snapshot(
      controls: const [
        PostEditFormField(
          name: 'message',
          value: 'old',
          controlKind: PostEditFormControlKind.textarea,
        ),
        PostEditFormField(
          name: 'fid',
          value: '5',
          controlKind: PostEditFormControlKind.hidden,
        ),
        PostEditFormField(
          name: 'tid',
          value: '20',
          controlKind: PostEditFormControlKind.hidden,
        ),
        PostEditFormField(
          name: 'pid',
          value: '30',
          controlKind: PostEditFormControlKind.hidden,
        ),
        PostEditFormField(
          name: 'attachupdate[12][description]',
          value: 'old',
          controlKind: PostEditFormControlKind.hidden,
        ),
      ],
    );
    final payload = const PostEditSubmitPayloadBuilder().build(
      PostEditSubmitCommand(
        target: snapshot.target,
        snapshot: snapshot,
        message: 'new',
        imageAttachments: const [],
        attachmentSession: PostEditAttachmentSession.fromImages(
          const [],
          deletedAidTombstones: {'12'},
        ),
        now: DateTime(2026, 8, 1),
      ),
    );

    expect(payload.fields.map((entry) => '${entry.key}=${entry.value}'), [
      'message=new',
      'fid=5',
      'tid=20',
      'pid=30',
      'editsubmit=yes',
    ]);
  });

  test('rejects a target or action mismatch', () {
    final snapshot = _snapshot(
      submitUri:
          'https://bbs.yamibo.com/forum.php?mod=post&action=reply&editsubmit=yes',
      controls: const [
        PostEditFormField(
          name: 'message',
          value: 'old',
          controlKind: PostEditFormControlKind.textarea,
        ),
      ],
    );

    expect(
      () => const PostEditSubmitPayloadBuilder().build(
        PostEditSubmitCommand(
          target: snapshot.target,
          snapshot: snapshot,
          message: 'new',
          imageAttachments: const [],
          attachmentSession: PostEditAttachmentSession.fromImages(const []),
          now: DateTime(2026, 8, 1),
        ),
      ),
      throwsA(
        isA<PostEditSubmitPayloadBuildException>().having(
          (error) => error.failure,
          'failure',
          PostEditSubmitPayloadBuildFailure.invalidSubmitUri,
        ),
      ),
    );
  });
}

PostEditFormSnapshot _snapshot({
  String? submitUri,
  required List<PostEditFormField> controls,
}) {
  final target = PostEditTarget(
    editUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=20&pid=30',
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
    submitUri: Uri.parse(
      submitUri ??
          'https://bbs.yamibo.com/forum.php?mod=post&action=edit&editsubmit=yes',
    ),
    formHash: 'hash',
    postTime: '123',
    rawMessage: '服务器正文',
    originalSubject: '标题',
    successfulControls: controls,
    existingImages: const [],
    structureEvidence: PostEditFormStructureEvidence(
      allNamedControlNamesInDomOrder: [
        for (final control in controls) control.name,
      ],
    ),
    baselineFingerprint: 'baseline',
  );
}
