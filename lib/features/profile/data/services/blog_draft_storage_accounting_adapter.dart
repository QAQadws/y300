import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/profile/domain/repositories/blog_draft_repository.dart';

class BlogDraftStorageAccountingAdapter implements StorageAccountingAdapter {
  const BlogDraftStorageAccountingAdapter({
    required BlogDraftRepository repository,
  }) : _repository = repository;

  final BlogDraftRepository _repository;

  @override
  StorageBucket get bucket => StorageBucket.composerDraft;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final usage = await _repository.usage();
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: usage.bytes,
      clearable: false,
      slices: [
        if (usage.bytes > 0)
          StorageUsageSlice(
            id: 'composer_draft:blog',
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.composerDraft,
              code: 'blog_draft',
              count: usage.count,
            ),
            bytes: usage.bytes,
            protected: true,
          ),
      ],
    );
  }
}
