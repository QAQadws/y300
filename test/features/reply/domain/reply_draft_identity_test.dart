import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

void main() {
  group('ReplyDraftIdentity', () {
    test('thread identity uses fid and tid as storage key', () {
      const identity = ReplyDraftIdentity.thread(fid: '33', tid: '572063');

      expect(identity.storageKey, 'thread:33:572063');
      expect(identity.isThreadReply, isTrue);
      expect(identity.isPostReply, isFalse);
      expect(identity.repquote, isNull);
    });

    test('post identity uses fid tid and repquote as storage key', () {
      const identity = ReplyDraftIdentity.post(
        fid: '33',
        tid: '572063',
        repquote: '41554317',
      );

      expect(identity.storageKey, 'post:33:572063:41554317');
      expect(identity.isThreadReply, isFalse);
      expect(identity.isPostReply, isTrue);
      expect(identity.repquote, '41554317');
    });
  });
}
