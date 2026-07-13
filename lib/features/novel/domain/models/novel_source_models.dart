import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';

class NovelSourceCatalogEntry {
  const NovelSourceCatalogEntry({
    required this.position,
    required this.pid,
    required this.title,
    required this.url,
  });

  final int position;
  final String pid;
  final String title;
  final String url;
}

class NovelSourceMetadata {
  const NovelSourceMetadata({
    required this.novelId,
    required this.tid,
    required this.fid,
    required this.subject,
    required this.publisherName,
    required this.publisherId,
    required this.firstPostPid,
    required this.catalogEntries,
    required this.sourceIntro,
    required this.coverImageUrl,
    required this.sourceApiVersion,
    required this.ingestedAt,
  });

  final String novelId;
  final String tid;
  final String fid;
  final String subject;
  final String publisherName;
  final String publisherId;
  final String firstPostPid;
  final List<NovelSourceCatalogEntry> catalogEntries;
  final String? sourceIntro;
  final String? coverImageUrl;
  final int sourceApiVersion;
  final DateTime ingestedAt;
}

class NovelSourceSeed {
  const NovelSourceSeed({
    required this.fid,
    required this.tid,
    this.typeid,
    this.tagName,
  });

  final String fid;
  final String tid;
  final String? typeid;
  final String? tagName;
}

enum NovelChapterHydrationState {
  metadataOnly,
  hydrating,
  ready,
  failed,
  legacyNeedsRebuild,
}

extension NovelChapterHydrationStateCodec on NovelChapterHydrationState {
  String get storageValue => name;

  static NovelChapterHydrationState fromStorage(String value) {
    return NovelChapterHydrationState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => throw FormatException(
        'Unknown novel chapter hydration state: $value',
      ),
    );
  }
}

class NovelSourceState {
  const NovelSourceState({
    required this.novelId,
    required this.publisherId,
    required this.publisherName,
    required this.firstPostPid,
    required this.sourceIntro,
    required this.catalogEntries,
    required this.metadataSourceVersion,
    required this.hydrationState,
    required this.metadataIngestedAt,
    required this.chaptersHydratedAt,
    required this.lastCompletedAuthorPage,
    required this.lastSeenPid,
    required this.lastSyncAt,
    required this.lastError,
  });

  final String novelId;
  final String? publisherId;
  final String? publisherName;
  final String? firstPostPid;
  final String? sourceIntro;
  final List<NovelSourceCatalogEntry> catalogEntries;
  final int? metadataSourceVersion;
  final NovelChapterHydrationState hydrationState;
  final DateTime? metadataIngestedAt;
  final DateTime? chaptersHydratedAt;
  final int lastCompletedAuthorPage;
  final String? lastSeenPid;
  final DateTime? lastSyncAt;
  final String? lastError;

  NovelChapterSyncCheckpoint? get checkpoint {
    final normalizedPublisherId = publisherId?.trim();
    final completedAt = lastSyncAt;
    if (normalizedPublisherId == null ||
        normalizedPublisherId.isEmpty ||
        lastCompletedAuthorPage <= 0 ||
        completedAt == null) {
      return null;
    }
    return NovelChapterSyncCheckpoint(
      novelId: novelId,
      publisherId: normalizedPublisherId,
      lastCompletedAuthorPage: lastCompletedAuthorPage,
      lastSeenPid: lastSeenPid,
      completedAt: completedAt,
    );
  }
}
