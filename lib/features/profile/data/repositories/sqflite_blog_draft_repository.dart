import 'package:sqflite/sqflite.dart';
import 'package:y300/features/profile/data/local/blog_draft_database.dart';
import 'package:y300/features/profile/data/services/blog_draft_codec.dart';
import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';
import 'package:y300/features/profile/domain/repositories/blog_draft_repository.dart';

final class SqfliteBlogDraftRepository implements BlogDraftRepository {
  SqfliteBlogDraftRepository({
    required Future<Database> Function() databaseProvider,
  }) : _databaseProvider = databaseProvider;
  final Future<Database> Function() _databaseProvider;
  final _codec = const BlogDraftCodec();
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<BlogDraftSnapshot?> load(String accountId) => _serial(() async {
    final rows = await (await _databaseProvider()).query(
      BlogDraftDatabase.table,
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    // Invalid payloads remain on disk until the user explicitly resets them.
    return rows.isEmpty
        ? null
        : _codec.decode(
            rows.single['snapshot_json'] as String,
            accountId: accountId,
          );
  });

  @override
  Future<void> save(BlogDraftSnapshot snapshot) => _serial(() async {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(snapshot.accountId)) {
      throw const FormatException('blog_draft_identity_invalid');
    }
    await (await _databaseProvider()).insert(BlogDraftDatabase.table, {
      'account_id': snapshot.accountId,
      'snapshot_json': _codec.encode(snapshot),
      'updated_at': snapshot.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  @override
  Future<void> delete(String accountId) => _serial(() async {
    await (await _databaseProvider()).delete(
      BlogDraftDatabase.table,
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
  });

  @override
  Future<BlogDraftUsage> usage() => _serial(() async {
    final rows = await (await _databaseProvider()).rawQuery('''
      SELECT COUNT(*) AS count,
        COALESCE(SUM(LENGTH(CAST(snapshot_json AS BLOB))), 0) AS bytes
      FROM ${BlogDraftDatabase.table}
    ''');
    return BlogDraftUsage(
      count: (rows.single['count'] as num).toInt(),
      bytes: (rows.single['bytes'] as num).toInt(),
    );
  });
}
