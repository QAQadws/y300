abstract class ComicCatalogMissPolicy {
  bool shouldQueueSearchOnCatalogMiss({
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  });
}

class DefaultComicCatalogMissPolicy implements ComicCatalogMissPolicy {
  const DefaultComicCatalogMissPolicy({
    this.longRunningTagName = '長篇連載',
  });

  final String longRunningTagName;

  @override
  bool shouldQueueSearchOnCatalogMiss({
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  }) {
    if (forceSearchOnCatalogMiss) {
      return true;
    }
    return _nonEmptyOrNull(sourceTagName) == _nonEmptyOrNull(longRunningTagName);
  }

  String? _nonEmptyOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
