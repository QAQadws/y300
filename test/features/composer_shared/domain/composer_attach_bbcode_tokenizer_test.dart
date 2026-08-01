import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_tokenizer.dart';

void main() {
  group('ComposerAttachBbCodeTokenizer', () {
    const tokenizer = ComposerAttachBbCodeTokenizer();

    test('converts known attach code to preview tag', () {
      expect(
        tokenizer.encodeForPreview('正文\n[attach]123[/attach]', [
          _uploadedAttachment(aid: '123'),
        ]),
        '正文\n[y300attach]123[/y300attach]',
      );
    });

    test('keeps unknown aid as source text', () {
      expect(
        tokenizer.encodeForPreview('正文\n[attach]999[/attach]', [
          _uploadedAttachment(aid: '123'),
        ]),
        '正文\n[attach]999[/attach]',
      );
    });

    test('converts multiple attach codes in source order', () {
      expect(
        tokenizer.encodeForPreview(
          '[attach]123[/attach]\n文字\n[attach]456[/attach]',
          [_uploadedAttachment(aid: '456'), _uploadedAttachment(aid: '123')],
        ),
        '[y300attach]123[/y300attach]\n文字\n[y300attach]456[/y300attach]',
      );
    });

    test('ignores non-uploaded attachments', () {
      expect(
        tokenizer.encodeForPreview('[attach]123[/attach]', [
          _uploadedAttachment(
            aid: '123',
            status: ComposerImageAttachmentStatus.failed,
          ),
        ]),
        '[attach]123[/attach]',
      );
    });

    test('does not alter stickers or ordinary BBCode', () {
      expect(
        tokenizer.encodeForPreview('[b]正文[/b]{:9_656:}[attach]123[/attach]', [
          _uploadedAttachment(aid: '123'),
        ]),
        '[b]正文[/b]{:9_656:}[y300attach]123[/y300attach]',
      );
    });
  });
}

ComposerImageAttachment _uploadedAttachment({
  required String aid,
  ComposerImageAttachmentStatus status = ComposerImageAttachmentStatus.uploaded,
}) {
  return ComposerImageAttachment(
    localId: 'local-$aid',
    localPath: '/gallery/$aid.jpg',
    fileName: '$aid.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: status,
    aid: aid,
    uploadedAt: DateTime.utc(2026, 6, 8),
  );
}
