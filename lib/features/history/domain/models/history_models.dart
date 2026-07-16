enum HistoryTargetType { thread, comic, novel }

enum HistoryVisitSurface {
  threadNative,
  threadWebView,
  comicDetail,
  novelDetail,
}

class HistoryTargetKey {
  const HistoryTargetKey({required this.type, required this.id});

  final HistoryTargetType type;
  final String id;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HistoryTargetKey && other.type == type && other.id == id;
  }

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => '${type.name}:$id';
}

class HistoryThumbnailSnapshot {
  const HistoryThumbnailSnapshot({
    this.localPath,
    this.remoteUrl,
    this.focusX,
    this.focusY,
  });

  final String? localPath;
  final String? remoteUrl;
  final double? focusX;
  final double? focusY;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HistoryThumbnailSnapshot &&
            other.localPath == localPath &&
            other.remoteUrl == remoteUrl &&
            other.focusX == focusX &&
            other.focusY == focusY;
  }

  @override
  int get hashCode => Object.hash(localPath, remoteUrl, focusX, focusY);
}

class HistoryVisitDraft {
  const HistoryVisitDraft({
    required this.target,
    required this.surface,
    this.title,
    this.contextLabel,
    this.thumbnail,
    this.sourceTid,
    this.canonicalUri,
    this.page,
    this.forumName,
  });

  final HistoryTargetKey target;
  final HistoryVisitSurface surface;
  final String? title;
  final String? contextLabel;
  final HistoryThumbnailSnapshot? thumbnail;
  final String? sourceTid;
  final Uri? canonicalUri;
  final int? page;
  final String? forumName;
}

class HistoryEntry {
  const HistoryEntry({
    required this.target,
    required this.title,
    required this.contextLabel,
    required this.lastSurface,
    required this.firstVisitedAt,
    required this.lastVisitedAt,
    required this.visitCount,
    this.thumbnail,
    this.sourceTid,
    this.canonicalUri,
    this.lastPage,
    this.forumName,
  });

  final HistoryTargetKey target;
  final String title;
  final String contextLabel;
  final HistoryThumbnailSnapshot? thumbnail;
  final String? sourceTid;
  final Uri? canonicalUri;
  final int? lastPage;
  final String? forumName;
  final HistoryVisitSurface lastSurface;
  final DateTime firstVisitedAt;
  final DateTime lastVisitedAt;
  final int visitCount;

  HistoryCursor get cursor => HistoryCursor(
    lastVisitedAt: lastVisitedAt,
    targetType: target.type,
    targetId: target.id,
  );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HistoryEntry &&
            other.target == target &&
            other.title == title &&
            other.contextLabel == contextLabel &&
            other.thumbnail == thumbnail &&
            other.sourceTid == sourceTid &&
            other.canonicalUri?.toString() == canonicalUri?.toString() &&
            other.lastPage == lastPage &&
            other.forumName == forumName &&
            other.lastSurface == lastSurface &&
            other.firstVisitedAt == firstVisitedAt &&
            other.lastVisitedAt == lastVisitedAt &&
            other.visitCount == visitCount;
  }

  @override
  int get hashCode => Object.hash(
    target,
    title,
    contextLabel,
    thumbnail,
    sourceTid,
    canonicalUri?.toString(),
    lastPage,
    forumName,
    lastSurface,
    firstVisitedAt,
    lastVisitedAt,
    visitCount,
  );
}

class HistoryCursor {
  const HistoryCursor({
    required this.lastVisitedAt,
    required this.targetType,
    required this.targetId,
  });

  final DateTime lastVisitedAt;
  final HistoryTargetType targetType;
  final String targetId;
}

class HistoryQuery {
  const HistoryQuery({
    this.searchText = '',
    this.targetTypes = const <HistoryTargetType>{},
    this.cursor,
    this.limit = 50,
  });

  final String searchText;
  final Set<HistoryTargetType> targetTypes;
  final HistoryCursor? cursor;
  final int limit;

  HistoryQuery copyWith({
    String? searchText,
    Set<HistoryTargetType>? targetTypes,
    HistoryCursor? cursor,
    bool clearCursor = false,
    int? limit,
  }) {
    return HistoryQuery(
      searchText: searchText ?? this.searchText,
      targetTypes: targetTypes ?? this.targetTypes,
      cursor: clearCursor ? null : (cursor ?? this.cursor),
      limit: limit ?? this.limit,
    );
  }
}

class HistoryQueryPage {
  const HistoryQueryPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<HistoryEntry> items;
  final bool hasMore;
  final HistoryCursor? nextCursor;
}

enum HistoryChangeKind { recorded, deleted, restored, cleared }

class HistoryChange {
  const HistoryChange({required this.kind, this.target});

  final HistoryChangeKind kind;
  final HistoryTargetKey? target;
}
