abstract class ComicCatalogMissPolicy {
  bool shouldQueueSearchOnCatalogMiss({
    String? sourceFid,
    String? sourceTypeId,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  });
}

class DefaultComicCatalogMissPolicy implements ComicCatalogMissPolicy {
  const DefaultComicCatalogMissPolicy({
    this.comicForumFid = '30',
    this.longRunningTypeId = '69',
    this.longRunningTagName = '長篇連載',
  });

  final String comicForumFid;
  final String longRunningTypeId;
  final String longRunningTagName;

  @override
  bool shouldQueueSearchOnCatalogMiss({
    String? sourceFid,
    String? sourceTypeId,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  }) {
    if (forceSearchOnCatalogMiss) {
      return true;
    }
    if (_isLongRunningType(sourceFid: sourceFid, sourceTypeId: sourceTypeId)) {
      return true;
    }
    return _nonEmptyOrNull(sourceTagName) ==
        _nonEmptyOrNull(longRunningTagName);
  }

  bool _isLongRunningType({String? sourceFid, String? sourceTypeId}) {
    final normalizedTypeId = _nonEmptyOrNull(sourceTypeId);
    if (normalizedTypeId != _nonEmptyOrNull(longRunningTypeId)) {
      return false;
    }
    final normalizedFid = _nonEmptyOrNull(sourceFid);
    return normalizedFid == null ||
        normalizedFid == _nonEmptyOrNull(comicForumFid);
  }

  String? _nonEmptyOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
