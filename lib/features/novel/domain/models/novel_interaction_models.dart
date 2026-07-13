enum NovelChapterOpenMode { reader, sourcePost }

extension NovelChapterOpenModeCodec on NovelChapterOpenMode {
  String get storageValue => name;

  static NovelChapterOpenMode fromStorage(String? value) {
    return NovelChapterOpenMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => NovelChapterOpenMode.reader,
    );
  }
}

class NovelChapterSourceReference {
  const NovelChapterSourceReference({required this.tid, required this.pid});

  final String tid;
  final String pid;
}

class NovelChapterSourceRoute {
  const NovelChapterSourceRoute({
    required this.tid,
    required this.pid,
    required this.page,
    required this.url,
  });

  final String tid;
  final String pid;
  final int page;
  final String url;
}

class NovelChapterSourceRouteException implements Exception {
  const NovelChapterSourceRouteException(this.message);

  final String message;

  @override
  String toString() => message;
}
