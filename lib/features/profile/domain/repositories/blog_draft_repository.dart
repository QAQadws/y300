import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';

abstract interface class BlogDraftRepository {
  Future<BlogDraftSnapshot?> load(String accountId);
  Future<void> save(BlogDraftSnapshot snapshot);
  Future<void> delete(String accountId);
  Future<BlogDraftUsage> usage();
}
