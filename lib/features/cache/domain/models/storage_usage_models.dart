enum StorageBucket {
  imageCache('image_cache', '图片缓存'),
  pageCache('page_cache', '页面缓存'),
  libraryMetadata('library_metadata', '书架数据'),
  composerDraft('composer_draft', '草稿'),
  download('download', '下载内容'),
  appSettings('app_settings', '应用设置');

  const StorageBucket(this.id, this.label);

  final String id;
  final String label;
}

enum CacheNamespace {
  image('image'),
  catalog('catalog'),
  document('document'),
  snapshot('snapshot'),
  draft('draft'),
  downloadIndex('download_index');

  const CacheNamespace(this.id);

  final String id;
}

enum CacheOwnerType {
  forum('forum'),
  forumDisplay('forum_display'),
  thread('thread'),
  tag('tag'),
  profile('profile'),
  blog('blog'),
  sticker('sticker'),
  comic('comic'),
  novel('novel'),
  favorite('favorite'),
  composer('composer');

  const CacheOwnerType(this.id);

  final String id;
}

class StorageUsageReport {
  const StorageUsageReport({
    required this.totalBytes,
    required this.sections,
    required this.calculatedAt,
  });

  factory StorageUsageReport.fromSections({
    required List<StorageUsageSection> sections,
    required DateTime calculatedAt,
  }) {
    final total = sections.fold<int>(0, (sum, section) => sum + section.bytes);
    return StorageUsageReport(
      totalBytes: total,
      sections: List.unmodifiable(sections),
      calculatedAt: calculatedAt,
    );
  }

  final int totalBytes;
  final List<StorageUsageSection> sections;
  final DateTime calculatedAt;
}

class StorageUsageSection {
  const StorageUsageSection({
    required this.bucket,
    required this.label,
    required this.bytes,
    required this.clearable,
    this.slices = const <StorageUsageSlice>[],
    this.categories = const <StorageUsageCategory>[],
  });

  final StorageBucket bucket;
  final String label;
  final int bytes;
  final bool clearable;
  final List<StorageUsageSlice> slices;
  final List<StorageUsageCategory> categories;
}

class StorageUsageCategory {
  const StorageUsageCategory({
    required this.id,
    required this.label,
    required this.bytes,
    required this.clearable,
    required this.protected,
  });

  final String id;
  final String label;
  final int bytes;
  final bool clearable;
  final bool protected;
}

class StorageUsageSlice {
  const StorageUsageSlice({
    required this.id,
    required this.label,
    required this.bytes,
    required this.protected,
  });

  final String id;
  final String label;
  final int bytes;
  final bool protected;
}

abstract class StorageAccountingAdapter {
  StorageBucket get bucket;

  Future<StorageUsageSection> calculateUsage();
}

abstract class StorageAccountingService {
  Future<StorageUsageReport> loadUsageReport();
}
