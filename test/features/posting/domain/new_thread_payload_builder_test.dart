import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/new_thread_payload_builder.dart';

void main() {
  const builder = DefaultNewThreadPayloadBuilder();

  group('DefaultNewThreadPayloadBuilder', () {
    test('uses default typeid 0 when nothing selected', () {
      final payload = builder.build(
        input: const NewThreadDraftInput(
          subject: ' 标题  ',
          message: '正文',
          selectedTypeId: null,
          useSignature: true,
          allowNoticeAuthor: false,
          bbCodeOff: false,
          smileyOff: false,
          parseUrlOff: false,
        ),
        metadata: _metadata(),
      );

      expect(payload.fid, '33');
      expect(payload.formHash, 'fh');
      expect(payload.subject, '标题');
      expect(payload.message, '正文');
      expect(payload.typeid, '0');
      expect(payload.useSignature, isTrue);
      expect(payload.allowNoticeAuthor, isFalse);
      expect(payload.bbCodeOff, isFalse);
      expect(payload.smileyOff, isFalse);
      expect(payload.parseUrlOff, isFalse);
      expect(payload.uploadedAttachmentAids, isEmpty);
    });

    test('keeps selected typeid when present in metadata list', () {
      final payload = builder.build(
        input: const NewThreadDraftInput(
          subject: '标题',
          message: '正文',
          selectedTypeId: '101',
          useSignature: false,
          allowNoticeAuthor: true,
          bbCodeOff: true,
          smileyOff: true,
          parseUrlOff: true,
        ),
        metadata: _metadata(),
      );

      expect(payload.typeid, '101');
      expect(payload.useSignature, isFalse);
      expect(payload.allowNoticeAuthor, isTrue);
      expect(payload.bbCodeOff, isTrue);
      expect(payload.smileyOff, isTrue);
      expect(payload.parseUrlOff, isTrue);
    });

    test('falls back to 0 when selected typeid is no longer in metadata', () {
      final payload = builder.build(
        input: const NewThreadDraftInput(
          subject: '标题',
          message: '正文',
          selectedTypeId: '999',
          useSignature: true,
          allowNoticeAuthor: false,
          bbCodeOff: false,
          smileyOff: false,
          parseUrlOff: false,
        ),
        metadata: _metadata(),
      );
      expect(payload.typeid, '0');
    });

    test('attaches uploaded aids in message order, deduped', () {
      final payload = builder.build(
        input: NewThreadDraftInput(
          subject: '标题',
          message: '[attach]222[/attach]\n正文\n[attach]111[/attach]\n[attach]222[/attach]',
          selectedTypeId: '101',
          useSignature: true,
          allowNoticeAuthor: false,
          bbCodeOff: false,
          smileyOff: false,
          parseUrlOff: false,
          imageAttachments: [
            _uploaded(localId: 'a', aid: '111'),
            _uploaded(localId: 'b', aid: '222'),
          ],
        ),
        metadata: _metadata(),
      );

      expect(payload.uploadedAttachmentAids, ['222', '111']);
    });

    test('skips attachments without uploaded status / aid', () {
      final payload = builder.build(
        input: NewThreadDraftInput(
          subject: '标题',
          message: '[attach]111[/attach][attach]222[/attach][attach]333[/attach]',
          selectedTypeId: null,
          useSignature: true,
          allowNoticeAuthor: false,
          bbCodeOff: false,
          smileyOff: false,
          parseUrlOff: false,
          imageAttachments: [
            ComposerImageAttachment(
              localId: 'a',
              localPath: '/x/a.jpg',
              fileName: 'a.jpg',
              mimeType: 'image/jpeg',
              order: 0,
              status: ComposerImageAttachmentStatus.local,
              aid: '111',
            ),
            _uploaded(localId: 'b', aid: '222'),
            ComposerImageAttachment(
              localId: 'c',
              localPath: '/x/c.jpg',
              fileName: 'c.jpg',
              mimeType: 'image/jpeg',
              order: 2,
              status: ComposerImageAttachmentStatus.failed,
              aid: '333',
              errorMessage: 'oops',
            ),
          ],
        ),
        metadata: _metadata(),
      );

      expect(payload.uploadedAttachmentAids, ['222']);
    });

    test('skips uploaded attachment when its attach code was removed from message',
        () {
      final payload = builder.build(
        input: NewThreadDraftInput(
          subject: '标题',
          message: '正文',
          selectedTypeId: null,
          useSignature: true,
          allowNoticeAuthor: false,
          bbCodeOff: false,
          smileyOff: false,
          parseUrlOff: false,
          imageAttachments: [
            _uploaded(localId: 'a', aid: '111'),
          ],
        ),
        metadata: _metadata(),
      );
      expect(payload.uploadedAttachmentAids, isEmpty);
    });
  });
}

NewThreadFormMetadata _metadata() {
  return const NewThreadFormMetadata(
    fid: '33',
    forumName: '随便聊聊',
    formHash: 'fh',
    threadTypes: [
      ThreadType(id: '101', name: '杂谈'),
      ThreadType(id: '102', name: '资源'),
    ],
    threadSorts: <ThreadSort>[],
    typeRequired: false,
    sortRequired: false,
  );
}

ComposerImageAttachment _uploaded({
  required String localId,
  required String aid,
}) {
  return ComposerImageAttachment(
    localId: localId,
    localPath: '/x/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: ComposerImageAttachmentStatus.uploaded,
    aid: aid,
    uploadedAt: DateTime.utc(2026, 6, 12),
  );
}
