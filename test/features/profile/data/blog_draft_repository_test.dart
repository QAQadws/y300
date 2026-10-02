import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/profile/data/local/blog_draft_database.dart';
import 'package:y300/features/profile/data/repositories/sqflite_blog_draft_repository.dart';
import 'package:y300/features/profile/data/services/blog_draft_codec.dart';
import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'SQLite close reopen retains exact source and account isolation without expiry',
    () async {
      final temp = await Directory.systemTemp.createTemp('blog_draft_test_');
      final path = '${temp.path}/draft.db';
      var db = await BlogDraftDatabase.open(databaseName: path);
      final repo = SqfliteBlogDraftRepository(databaseProvider: () async => db);
      addTearDown(() async {
        await db.close();
        await temp.delete(recursive: true);
      });
      final source = BlogDraftSnapshot(
        accountId: '101',
        updatedAt: DateTime.utc(2000),
        subject: '原始标题',
        bodyHtml: '<table><tr><td><b>换行</b><br>😊</td></tr></table>',
        targetNames: 'Reader 一',
        visibility: UserBlogVisibility.selectedFriends,
        creatingCategory: true,
        newPersonalCategory: '新分类',
        pendingSubmission: true,
        images: [
          BlogDraftImage(
            picId: '77',
            originalUri: Uri.parse('https://example.test/77.png'),
          ),
        ],
      );
      await repo.save(source);
      await repo.save(
        BlogDraftSnapshot(
          accountId: '202',
          updatedAt: DateTime.now(),
          subject: 'other',
        ),
      );
      await db.close();
      db = await BlogDraftDatabase.open(databaseName: path);
      final restored = (await repo.load('101'))!;
      expect(restored.bodyHtml, source.bodyHtml);
      expect(restored.targetNames, 'Reader 一');
      expect(restored.visibility, UserBlogVisibility.selectedFriends);
      expect(restored.pendingSubmission, isTrue);
      expect(restored.creatingCategory, isTrue);
      expect(restored.images.single.picId, '77');
      expect((await repo.usage()).count, 2);
      expect((await repo.usage()).bytes, greaterThan(0));
      await repo.delete('101');
      expect(await repo.load('101'), isNull);
      expect((await repo.load('202'))!.subject, 'other');
    },
  );
  test(
    'invalid payload is preserved instead of being treated as an empty draft',
    () async {
      final db = await BlogDraftDatabase.open(
        databaseName: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      await db.insert(BlogDraftDatabase.table, {
        'account_id': '101',
        'snapshot_json': 'broken',
        'updated_at': 1,
      });
      final repo = SqfliteBlogDraftRepository(databaseProvider: () async => db);
      await expectLater(repo.load('101'), throwsFormatException);
      expect((await repo.usage()).count, 1);
    },
  );
  test(
    'codec rejects cross-account and future schema and has no credential fields',
    () {
      const codec = BlogDraftCodec();
      final raw = codec.encode(
        BlogDraftSnapshot(
          accountId: '101',
          updatedAt: DateTime.now(),
          visibility: UserBlogVisibility.passwordProtected,
        ),
      );
      expect(raw, isNot(contains('"password"')));
      expect(raw, isNot(contains('token')));
      expect(() => codec.decode(raw, accountId: '202'), throwsFormatException);
      expect(
        () => codec.decode(
          raw.replaceFirst('"version":1', '"version":2'),
          accountId: '101',
        ),
        throwsFormatException,
      );
    },
  );
}
