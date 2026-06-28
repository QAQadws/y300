import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_attachment_maintenance_service.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SharedPreferencesComposerDraftAttachmentMaintenanceService', () {
    test('sanitizes expired attachments across thread and post drafts',
        () async {
      final thread = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      final post = ComposerDraftIdentity.post(
        fid: '33',
        tid: '572063',
        repquote: '41554317',
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.${thread.storageKey}': _rawDraft(
          identity: thread,
          message: '正文\n[attach]111[/attach]',
          imageAttachments: [
            _rawAttachment(
              localId: 'expired',
              aid: '111',
              uploadedAt: DateTime.utc(2026, 6, 7, 12),
            ),
          ],
        ),
        'reply_draft.${post.storageKey}': _rawDraft(
          identity: post,
          message: '楼层\n[attach]222[/attach]',
          imageAttachments: [
            _rawAttachment(
              localId: 'fresh',
              aid: '222',
              uploadedAt: DateTime.utc(2026, 6, 8, 11),
            ),
          ],
        ),
      });
      final service =
          SharedPreferencesComposerDraftAttachmentMaintenanceService(
        now: () => DateTime.utc(2026, 6, 8, 12),
      );

      final result = await service.maintain();
      final prefs = await SharedPreferences.getInstance();

      expect(result.scannedDraftCount, 2);
      expect(result.sanitizedDraftCount, 1);
      expect(result.removedAttachmentCount, 1);
      expect(
        prefs.getString('reply_draft.${thread.storageKey}'),
        contains('"message":"正文"'),
      );
      expect(
        prefs.getString('reply_draft.${thread.storageKey}'),
        isNot(contains('[attach]111[/attach]')),
      );
      expect(
        prefs.getString('reply_draft.${post.storageKey}'),
        contains('[attach]222[/attach]'),
      );
    });

    test('deletes only owned cachePath files, not original localPath', () async {
      final fileSystem = MemoryFileSystem();
      final ownedCachePath = '/cache/reply_uploads/thread/image.jpg';
      final outsideCachePath = '/gallery/cache-copy.jpg';
      final originalPath = '/gallery/original.jpg';
      fileSystem.file(ownedCachePath)
        ..createSync(recursive: true)
        ..writeAsStringSync('owned');
      fileSystem.file(outsideCachePath)
        ..createSync(recursive: true)
        ..writeAsStringSync('outside');
      fileSystem.file(originalPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('original');
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.${identity.storageKey}': _rawDraft(
          identity: identity,
          message: '[attach]111[/attach]\n[attach]222[/attach]',
          imageAttachments: [
            _rawAttachment(
              localId: 'owned',
              aid: '111',
              uploadedAt: DateTime.utc(2026, 6, 7, 12),
              localPath: originalPath,
              cachePath: ownedCachePath,
            ),
            _rawAttachment(
              localId: 'outside',
              aid: '222',
              uploadedAt: DateTime.utc(2026, 6, 7, 12),
              localPath: originalPath,
              cachePath: outsideCachePath,
            ),
          ],
        ),
      });
      final service =
          SharedPreferencesComposerDraftAttachmentMaintenanceService(
        cacheStorage: LocalComposerUploadCacheStorage(
          fileSystem: fileSystem,
          cacheRootPath: () async => '/cache/reply_uploads',
        ),
        now: () => DateTime.utc(2026, 6, 8, 12),
      );

      final result = await service.maintain();

      expect(result.deletedCacheFileCount, 1);
      expect(fileSystem.file(ownedCachePath).existsSync(), isFalse);
      expect(fileSystem.file(outsideCachePath).existsSync(), isTrue);
      expect(fileSystem.file(originalPath).existsSync(), isTrue);
    });

    test('removes malformed drafts and reports failures without throwing',
        () async {
      final identity = ComposerDraftIdentity.thread(fid: '33', tid: '572063');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.thread:33:broken': '{not json',
        'reply_draft.${identity.storageKey}': _rawDraft(
          identity: identity,
          message: '[attach]111[/attach]',
          imageAttachments: [
            _rawAttachment(
              localId: 'expired',
              aid: '111',
              uploadedAt: DateTime.utc(2026, 6, 7, 12),
              cachePath: '/cache/reply_uploads/boom.jpg',
            ),
          ],
        ),
      });
      final service =
          SharedPreferencesComposerDraftAttachmentMaintenanceService(
        cacheStorage: _ThrowingComposerUploadCacheStorage(),
        now: () => DateTime.utc(2026, 6, 8, 12),
      );

      final result = await service.maintain();
      final prefs = await SharedPreferences.getInstance();

      expect(result.deletedDraftCount, 1);
      expect(result.failedDraftCount, 1);
      expect(prefs.getString('reply_draft.thread:33:broken'), isNull);
      expect(prefs.getString('reply_draft.${identity.storageKey}'), isNotNull);
    });
  });
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
  String? localPath,
  String? cachePath,
}) {
  return <String, Object?>{
    'localId': localId,
    'localPath': localPath ?? '/gallery/$localId.jpg',
    'fileName': '$localId.jpg',
    'mimeType': 'image/jpeg',
    'order': 0,
    'status': ComposerImageAttachmentStatus.uploaded.name,
    'aid': aid,
    'uploadedAt': uploadedAt.toIso8601String(),
    'errorMessage': null,
    'cachePath': cachePath,
  };
}

class _ThrowingComposerUploadCacheStorage implements ComposerUploadCacheStorage {
  @override
  Future<bool> deleteCachePathIfOwned(String? cachePath) {
    throw StateError('cache delete failed');
  }
}
