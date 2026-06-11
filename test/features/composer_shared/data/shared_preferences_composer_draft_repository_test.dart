import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/composer_shared/data/shared_preferences_composer_draft_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SharedPreferencesComposerDraftRepository', () {
    test('saves and loads thread draft', () async {
      final repository = SharedPreferencesComposerDraftRepository();
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');

      await repository.saveDraft(
        ComposerDraftSnapshot(
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
      expect(loaded.imageAttachments, isEmpty);
    });

    test('saves and loads draft image attachments', () async {
      final repository = SharedPreferencesComposerDraftRepository(
        now: () => DateTime.utc(2026, 6, 8, 12),
      );
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      final attachment = _attachment(
        localId: 'image-1',
        aid: '123456',
        uploadedAt: DateTime.utc(2026, 6, 8, 10),
      );

      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: identity,
          message: '正文\n[attach]123456[/attach]',
          useSignature: false,
          updatedAt: DateTime.utc(2026, 6, 8),
          imageAttachments: [attachment],
        ),
      );

      final loaded = await repository.loadDraft(identity);

      expect(loaded, isNotNull);
      expect(loaded!.message, '正文\n[attach]123456[/attach]');
      expect(loaded.imageAttachments, hasLength(1));
      expect(loaded.imageAttachments.single.localId, 'image-1');
      expect(loaded.imageAttachments.single.status,
          ComposerImageAttachmentStatus.uploaded);
      expect(loaded.imageAttachments.single.aid, '123456');
      expect(loaded.imageAttachments.single.uploadedAt,
          DateTime.utc(2026, 6, 8, 10));
    });

    test('keeps different thread drafts isolated', () async {
      final repository = SharedPreferencesComposerDraftRepository();
      final first = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      final second = ComposerDraftIdentity.thread(fid: '33', tid: '572064');

      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: first,
          message: 'first',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      await repository.saveDraft(
        ComposerDraftSnapshot(
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
      final repository = SharedPreferencesComposerDraftRepository();
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');

      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: identity,
          message: 'draft',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: identity,
          message: '   ',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 7),
        ),
      );

      expect(await repository.loadDraft(identity), isNull);
    });

    test('blank message with fresh image attachment keeps draft', () async {
      final repository = SharedPreferencesComposerDraftRepository(
        now: () => DateTime.utc(2026, 6, 8, 12),
      );
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');

      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: identity,
          message: '   ',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 8),
          imageAttachments: [
            _attachment(
              localId: 'image-1',
              aid: '123456',
              uploadedAt: DateTime.utc(2026, 6, 8, 10),
            ),
          ],
        ),
      );

      final loaded = await repository.loadDraft(identity);

      expect(loaded, isNotNull);
      expect(loaded!.message, '   ');
      expect(loaded.imageAttachments, hasLength(1));
    });

    test('delete removes saved draft', () async {
      final repository = SharedPreferencesComposerDraftRepository();
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');

      await repository.saveDraft(
        ComposerDraftSnapshot(
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
      final repository = SharedPreferencesComposerDraftRepository();

      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: ComposerDraftIdentity.thread(fid: '33', tid: '572063'),
          message: 'thread',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: ComposerDraftIdentity.post(
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
        ComposerDraftSnapshot(
          identity: ComposerDraftIdentity.thread(fid: '33', tid: '572064'),
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

    test('loads old draft format without imageAttachments', () async {
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.${identity.storageKey}': jsonEncode(<String, Object?>{
          'fid': '33',
          'tid': '572063',
          'message': '旧草稿',
          'useSignature': true,
          'updatedAt': DateTime.utc(2026, 6, 8).toIso8601String(),
        }),
      });
      final repository = SharedPreferencesComposerDraftRepository();

      final loaded = await repository.loadDraft(identity);

      expect(loaded, isNotNull);
      expect(loaded!.message, '旧草稿');
      expect(loaded.imageAttachments, isEmpty);
    });

    test('skips malformed attachment item without dropping draft body', () async {
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.${identity.storageKey}': _rawDraft(
          identity: identity,
          message: '正文',
          imageAttachments: [
            <String, Object?>{
              'localId': 'broken',
              'localPath': '/gallery/broken.jpg',
            },
            _rawAttachment(
              localId: 'valid',
              aid: '123456',
              uploadedAt: DateTime.utc(2026, 6, 8, 10),
            ),
          ],
        ),
      });
      final repository = SharedPreferencesComposerDraftRepository(
        now: () => DateTime.utc(2026, 6, 8, 12),
      );

      final loaded = await repository.loadDraft(identity);

      expect(loaded, isNotNull);
      expect(loaded!.message, '正文');
      expect(loaded.imageAttachments, hasLength(1));
      expect(loaded.imageAttachments.single.localId, 'valid');
    });

    test('loadDraft removes expired uploaded attachment and attach line',
        () async {
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.${identity.storageKey}': _rawDraft(
          identity: identity,
          message: '正文\n[attach]123456[/attach]\n[attach]654321[/attach]',
          imageAttachments: [
            _rawAttachment(
              localId: 'expired',
              aid: '123456',
              uploadedAt: DateTime.utc(2026, 6, 7, 12),
            ),
            _rawAttachment(
              localId: 'fresh',
              aid: '654321',
              uploadedAt: DateTime.utc(2026, 6, 8, 11),
            ),
          ],
        ),
      });
      final repository = SharedPreferencesComposerDraftRepository(
        now: () => DateTime.utc(2026, 6, 8, 12),
      );

      final loaded = await repository.loadDraft(identity);

      expect(loaded, isNotNull);
      expect(loaded!.message, '正文\n[attach]654321[/attach]');
      expect(loaded.imageAttachments.map((item) => item.localId), ['fresh']);
    });

    test('loadDraft keeps fresh uploaded attachment and attach line', () async {
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.${identity.storageKey}': _rawDraft(
          identity: identity,
          message: '正文\n[attach]123456[/attach]',
          imageAttachments: [
            _rawAttachment(
              localId: 'fresh',
              aid: '123456',
              uploadedAt: DateTime.utc(2026, 6, 8, 11),
            ),
          ],
        ),
      });
      final repository = SharedPreferencesComposerDraftRepository(
        now: () => DateTime.utc(2026, 6, 8, 12),
      );

      final loaded = await repository.loadDraft(identity);

      expect(loaded?.message, '正文\n[attach]123456[/attach]');
      expect(loaded?.imageAttachments, hasLength(1));
    });

    test('prunes drafts older than max age', () async {
      final repository = SharedPreferencesComposerDraftRepository();
      final oldIdentity = ComposerDraftIdentity.thread(fid: '33', tid: 'old');
      final recentIdentity =
          ComposerDraftIdentity.thread(fid: '33', tid: 'recent');
      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: oldIdentity,
          message: 'old',
          useSignature: true,
          updatedAt: DateTime.now().subtract(const Duration(days: 31)),
        ),
      );
      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: recentIdentity,
          message: 'recent',
          useSignature: true,
          updatedAt: DateTime.now(),
        ),
      );

      final result = await repository.pruneDrafts();

      expect(result.removedCount, 1);
      expect(await repository.loadDraft(oldIdentity), isNull);
      expect((await repository.loadDraft(recentIdentity))?.message, 'recent');
    });

    test('prunes drafts above max count keeping newest', () async {
      final repository = SharedPreferencesComposerDraftRepository();
      final baseTime = DateTime.now().subtract(const Duration(days: 1));
      for (var index = 0; index < 105; index += 1) {
        await repository.saveDraft(
          ComposerDraftSnapshot(
            identity: ComposerDraftIdentity.thread(fid: '33', tid: '$index'),
            message: 'draft-$index',
            useSignature: true,
            updatedAt: baseTime.add(Duration(minutes: index)),
          ),
        );
      }

      final result = await repository.pruneDrafts(maxCount: 100);

      expect(result.removedCount, 5);
      expect(
        await repository.loadDraft(
          ComposerDraftIdentity.thread(fid: '33', tid: '0'),
        ),
        isNull,
      );
      expect(
        (await repository.loadDraft(
          ComposerDraftIdentity.thread(fid: '33', tid: '104'),
        ))
            ?.message,
        'draft-104',
      );
    });

    test('keeps valid thread and post drafts during prune', () async {
      final repository = SharedPreferencesComposerDraftRepository();
      final threadIdentity = ComposerDraftIdentity.thread(
        fid: '33',
        tid: '572063',
      );
      final postIdentity = ComposerDraftIdentity.post(
        fid: '33',
        tid: '572063',
        repquote: '41554317',
      );

      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: threadIdentity,
          message: 'thread draft',
          useSignature: true,
          updatedAt: DateTime.now(),
        ),
      );
      await repository.saveDraft(
        ComposerDraftSnapshot(
          identity: postIdentity,
          message: 'post draft',
          useSignature: false,
          updatedAt: DateTime.now(),
        ),
      );

      final result = await repository.pruneDrafts();

      expect(result.removedCount, 0);
      expect(
        (await repository.loadDraft(threadIdentity))?.message,
        'thread draft',
      );
      expect((await repository.loadDraft(postIdentity))?.message, 'post draft');
    });

    test('prunes malformed draft payloads', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.thread:33:broken': '{not json',
        'reply_draft.thread:33:missing': '{"fid":"33"}',
        'reply_draft.thread:33:bad-date':
            '{"fid":"33","tid":"bad-date","message":"draft","updatedAt":"bad"}',
      });
      final repository = SharedPreferencesComposerDraftRepository();

      final result = await repository.pruneDrafts();

      expect(result.removedCount, 3);
      expect(
        await repository.loadDraft(
          ComposerDraftIdentity.thread(fid: '33', tid: 'broken'),
        ),
        isNull,
      );
    });

    test('pruneDrafts sanitizes expired attachments in kept drafts', () async {
      final first = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      final second = ComposerDraftIdentity.post(
        fid: '33',
        tid: '572063',
        repquote: '41554317',
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.${first.storageKey}': _rawDraft(
          identity: first,
          message: '正文\n[attach]111[/attach]',
          imageAttachments: [
            _rawAttachment(
              localId: 'expired-1',
              aid: '111',
              uploadedAt: DateTime.utc(2026, 6, 7, 12),
            ),
          ],
        ),
        'reply_draft.${second.storageKey}': _rawDraft(
          identity: second,
          message: '楼层\n[attach]222[/attach]',
          imageAttachments: [
            _rawAttachment(
              localId: 'fresh-1',
              aid: '222',
              uploadedAt: DateTime.utc(2026, 6, 8, 11),
            ),
          ],
        ),
      });
      final repository = SharedPreferencesComposerDraftRepository(
        now: () => DateTime.utc(2026, 6, 8, 12),
      );

      final result = await repository.pruneDrafts();

      expect(result.removedCount, 0);
      expect((await repository.loadDraft(first))?.message, '正文');
      expect((await repository.loadDraft(first))?.imageAttachments, isEmpty);
      expect(
        (await repository.loadDraft(second))?.message,
        '楼层\n[attach]222[/attach]',
      );
      expect(
        (await repository.loadDraft(second))?.imageAttachments,
        hasLength(1),
      );
    });
  });
}

ComposerImageAttachment _attachment({
  required String localId,
  required String aid,
  required DateTime uploadedAt,
}) {
  return ComposerImageAttachment(
    localId: localId,
    localPath: '/gallery/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: ComposerImageAttachmentStatus.uploaded,
    aid: aid,
    uploadedAt: uploadedAt,
    errorMessage: 'ignored',
    cachePath: '/cache/$localId.jpg',
  );
}

String _rawDraft({
  required ComposerDraftIdentity identity,
  required String message,
  required List<Map<String, Object?>> imageAttachments,
}) {
  return jsonEncode(<String, Object?>{
    'fid': identity.fid,
    'tid': identity.tid,
    'repquote': identity.repquote,
    'message': message,
    'useSignature': true,
    'updatedAt': DateTime.utc(2026, 6, 8).toIso8601String(),
    'imageAttachments': imageAttachments,
  });
}

Map<String, Object?> _rawAttachment({
  required String localId,
  required String aid,
  required DateTime uploadedAt,
}) {
  return <String, Object?>{
    'localId': localId,
    'localPath': '/gallery/$localId.jpg',
    'fileName': '$localId.jpg',
    'mimeType': 'image/jpeg',
    'order': 0,
    'status': ComposerImageAttachmentStatus.uploaded.name,
    'aid': aid,
    'uploadedAt': uploadedAt.toIso8601String(),
    'errorMessage': null,
    'cachePath': null,
  };
}
