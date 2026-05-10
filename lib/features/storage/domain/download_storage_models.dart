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

class DownloadedNovelChapter {
  const DownloadedNovelChapter({
    required this.novelId,
    required this.episodeId,
    required this.chapterPath,
  });

  final String novelId;
  final String episodeId;
  final String chapterPath;
}

class DownloadedNovelChapterImage {
  const DownloadedNovelChapterImage({
    required this.index,
    required this.file,
    required this.sourceUrl,
  });

  final int index;
  final String file;
  final String sourceUrl;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index': index,
      'file': file,
      'sourceUrl': sourceUrl,
    };
  }
}
