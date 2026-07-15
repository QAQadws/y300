enum ReaderImageSessionPreloadKind { decoded, disk }

abstract interface class ReaderImagePreparationSink {
  Future<void> record(ReaderImagePreparationRecord record);
}

class ReaderImagePreparationRecord {
  const ReaderImagePreparationRecord({
    required this.readerOwnerId,
    required this.itemId,
    required this.imageIndex,
    required this.sourceUrl,
    required this.generation,
    required this.decoded,
    this.cacheKey,
    this.localPath,
  });

  final String readerOwnerId;
  final String itemId;
  final int imageIndex;
  final String sourceUrl;
  final String? cacheKey;
  final String? localPath;
  final int generation;
  final bool decoded;
}
