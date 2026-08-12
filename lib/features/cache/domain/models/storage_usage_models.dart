enum StorageBucket {
  imageCache('image_cache'),
  libraryCover('library_cover'),
  pageCache('page_cache'),
  libraryMetadata('library_metadata'),
  history('history'),
  composerDraft('composer_draft'),
  download('download'),
  appSettings('app_settings');

  const StorageBucket(this.id);

  final String id;
}

enum StorageUsageLabelKind {
  bucket,
  imageRole,
  imageCategory,
  documentOwner,
  snapshotType,
  composerDraft,
  downloadKind,
  libraryKind,
  historyKind,
  database,
}

/// Stable semantic data for a storage usage label.
///
/// The cache/data layers return this descriptor instead of a localized
/// sentence.  The More presentation layer owns the actual localized text.
class StorageUsageLabelRef {
  const StorageUsageLabelRef({
    required this.kind,
    required this.code,
    this.count,
    this.qualifier,
  });

  final StorageUsageLabelKind kind;
  final String code;
  final int? count;
  final String? qualifier;
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
    required StorageBucket bucket,
    this.labelRef,
    @Deprecated('Use labelRef instead.') String? label,
    required this.bytes,
    required this.clearable,
    this.slices = const <StorageUsageSlice>[],
    this.categories = const <StorageUsageCategory>[],
  }) : bucket = bucket;

  final StorageBucket bucket;
  final StorageUsageLabelRef? labelRef;
  final int bytes;
  final bool clearable;
  final List<StorageUsageSlice> slices;
  final List<StorageUsageCategory> categories;
}

class StorageUsageCategory {
  const StorageUsageCategory({
    required String id,
    this.labelRef,
    @Deprecated('Use labelRef instead.') String? label,
    required this.bytes,
    required this.clearable,
    required this.protected,
  }) : id = id;

  final String id;
  final StorageUsageLabelRef? labelRef;
  final int bytes;
  final bool clearable;
  final bool protected;
}

class StorageUsageSlice {
  const StorageUsageSlice({
    required String id,
    this.labelRef,
    @Deprecated('Use labelRef instead.') String? label,
    required this.bytes,
    required this.protected,
  }) : id = id;

  final String id;
  final StorageUsageLabelRef? labelRef;
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
