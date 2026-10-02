import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';
import 'package:y300/features/profile/domain/repositories/blog_draft_repository.dart';

class MemoryBlogDraftRepository implements BlogDraftRepository {
  Future<void>? beforeSave;
  Future<void>? beforeLoad;
  final values = <String, BlogDraftSnapshot>{};
  bool failLoad = false, failSave = false, failDelete = false;
  @override
  Future<BlogDraftSnapshot?> load(String accountId) async {
    await beforeLoad;
    if (failLoad) throw StateError('load_failed');
    return values[accountId];
  }

  @override
  Future<void> save(BlogDraftSnapshot snapshot) async {
    await beforeSave;
    if (failSave) throw StateError('save_failed');
    values[snapshot.accountId] = snapshot;
  }

  @override
  Future<void> delete(String accountId) async {
    if (failDelete) throw StateError('delete_failed');
    values.remove(accountId);
  }

  @override
  Future<BlogDraftUsage> usage() async =>
      BlogDraftUsage(count: values.length, bytes: 100 * values.length);
}
