/// Persists a discovered catalog URL without changing a user's override.
abstract class CatalogUrlUpdater {
  Future<void> updateCatalogUrl({
    required String comicId,
    required String catalogUrl,
  });
}
