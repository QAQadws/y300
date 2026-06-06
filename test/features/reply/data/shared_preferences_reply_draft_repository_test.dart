import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reply/data/shared_preferences_reply_draft_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SharedPreferencesReplyDraftRepository', () {
    test('saves and loads thread draft', () async {
      final repository = SharedPreferencesReplyDraftRepository();
      final identity = ReplyDraftIdentity.thread(fid: '33', tid: '572063');

      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: identity,
          message: '未写完的回复',
          useSignature: false,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );

      final loaded = await repository.loadDraft(identity);

      expect(loaded, isNotNull);
      expect(loaded!.identity.storageKey, 'thread:33:572063');
      expect(loaded.message, '未写完的回复');
      expect(loaded.useSignature, isFalse);
      expect(loaded.updatedAt, DateTime.utc(2026, 6, 6));
    });

    test('keeps different thread drafts isolated', () async {
      final repository = SharedPreferencesReplyDraftRepository();
      final first = ReplyDraftIdentity.thread(fid: '33', tid: '572063');
      final second = ReplyDraftIdentity.thread(fid: '33', tid: '572064');

      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: first,
          message: 'first',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: second,
          message: 'second',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 7),
        ),
      );

      expect((await repository.loadDraft(first))?.message, 'first');
      expect((await repository.loadDraft(second))?.message, 'second');
    });

    test('blank message removes draft', () async {
      final repository = SharedPreferencesReplyDraftRepository();
      final identity = ReplyDraftIdentity.thread(fid: '33', tid: '572063');

      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: identity,
          message: 'draft',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: identity,
          message: '   ',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 7),
        ),
      );

      expect(await repository.loadDraft(identity), isNull);
    });

    test('delete removes saved draft', () async {
      final repository = SharedPreferencesReplyDraftRepository();
      final identity = ReplyDraftIdentity.thread(fid: '33', tid: '572063');

      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: identity,
          message: 'draft',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      await repository.deleteDraft(identity);

      expect(await repository.loadDraft(identity), isNull);
    });

    test('lists drafts for the same thread only', () async {
      final repository = SharedPreferencesReplyDraftRepository();

      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: ReplyDraftIdentity.thread(fid: '33', tid: '572063'),
          message: 'thread',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: ReplyDraftIdentity.post(
            fid: '33',
            tid: '572063',
            repquote: '41554317',
          ),
          message: 'post',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 7),
        ),
      );
      await repository.saveDraft(
        ReplyDraftSnapshot(
          identity: ReplyDraftIdentity.thread(fid: '33', tid: '572064'),
          message: 'other',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 8),
        ),
      );

      final drafts = await repository.listDraftsForThread(
        fid: '33',
        tid: '572063',
      );

      expect(drafts.map((draft) => draft.message), <String>['post', 'thread']);
    });
  });
}
