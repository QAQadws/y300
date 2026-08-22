enum ComicEpisodeImageOrigin { dom, attachment }

final class ComicEpisodeCatalogRequest {
  const ComicEpisodeCatalogRequest({required this.sourceTid});

  final String sourceTid;
}

final class ComicEpisodeImageReference {
  const ComicEpisodeImageReference({
    required this.url,
    required this.origin,
    this.attachmentId,
  });

  final String url;
  final ComicEpisodeImageOrigin origin;
  final String? attachmentId;
}

final class ComicEpisodeImageCatalog {
  const ComicEpisodeImageCatalog({
    required this.sourceTid,
    required this.images,
  });

  final String sourceTid;
  final List<ComicEpisodeImageReference> images;
}
