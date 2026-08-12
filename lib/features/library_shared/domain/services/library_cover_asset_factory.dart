import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

abstract final class LibraryCoverAssetFactory {
  static LibraryCoverAssetRef? preferred({
    required String ownerType,
    required String ownerId,
    String? sourceUrl,
    String? sourceLegacyPath,
    int sourceRevision = 0,
    String? customSourceUrl,
    String? customLegacyPath,
    int customRevision = 0,
  }) {
    final normalizedCustomUrl = _text(customSourceUrl);
    final normalizedCustomPath = _text(customLegacyPath);
    if (customRevision > 0 ||
        normalizedCustomUrl != null ||
        normalizedCustomPath != null) {
      return LibraryCoverAssetRef(
        assetId: LibraryCoverAssetIds.custom(
          ownerType: ownerType,
          ownerId: ownerId,
        ),
        revision: customRevision > 0 ? customRevision : 1,
        kind: LibraryCoverAssetKind.custom,
        sourceUrl: normalizedCustomUrl,
        legacyLocalPath: normalizedCustomPath,
      );
    }
    final normalizedSourceUrl = _text(sourceUrl);
    final normalizedSourcePath = _text(sourceLegacyPath);
    // Once migration has adopted a source cover, the legacy path and URL are
    // intentionally cleared. The revision is then the only durable evidence
    // that the work owns a source asset; keep returning the stable identity so
    // the dedicated Store can open its deterministic file without a network
    // lookup.
    if (sourceRevision <= 0 &&
        normalizedSourceUrl == null &&
        normalizedSourcePath == null) {
      return null;
    }
    return LibraryCoverAssetRef(
      assetId: LibraryCoverAssetIds.source(
        ownerType: ownerType,
        ownerId: ownerId,
      ),
      revision: sourceRevision > 0 ? sourceRevision : 1,
      kind: LibraryCoverAssetKind.source,
      sourceUrl: normalizedSourceUrl,
      legacyLocalPath: normalizedSourcePath,
    );
  }

  static String? _text(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
