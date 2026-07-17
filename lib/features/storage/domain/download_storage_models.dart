class DownloadStorageRoot {
  const DownloadStorageRoot({
    required this.path,
    required this.comicsPath,
    required this.novelsPath,
    required this.favoritesJsonPath,
  });

  final String path;
  final String comicsPath;
  final String novelsPath;
  final String favoritesJsonPath;
}

class DownloadedComicEpisode {
  const DownloadedComicEpisode({
    required this.workId,
    required this.episodeId,
    required this.cbzPath,
    required this.imageFiles,
  });

  final String workId;
  final String episodeId;
  final String cbzPath;
  final List<String> imageFiles;
}
