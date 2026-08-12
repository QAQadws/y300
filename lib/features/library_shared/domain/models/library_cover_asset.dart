import 'package:flutter/foundation.dart';

enum LibraryCoverAssetKind { source, custom }

/// A stable business identity for a library cover.
///
/// [legacyLocalPath] only exists to adopt files created by the retired cover
/// cache. It is deliberately excluded from equality and image cache keys.
@immutable
class LibraryCoverAssetRef {
  const LibraryCoverAssetRef({
    required this.assetId,
    required this.revision,
    required this.kind,
    this.sourceUrl,
    this.legacyLocalPath,
  });

  final String assetId;
  final int revision;
  final LibraryCoverAssetKind kind;
  final String? sourceUrl;
  final String? legacyLocalPath;

  String get versionedId => '$assetId@$revision';

  bool get canLoad {
    return _hasText(sourceUrl) || _hasText(legacyLocalPath);
  }

  LibraryCoverAssetRef copyWith({
    int? revision,
    String? sourceUrl,
    String? legacyLocalPath,
    bool clearSourceUrl = false,
    bool clearLegacyLocalPath = false,
  }) {
    return LibraryCoverAssetRef(
      assetId: assetId,
      revision: revision ?? this.revision,
      kind: kind,
      sourceUrl: clearSourceUrl ? null : (sourceUrl ?? this.sourceUrl),
      legacyLocalPath: clearLegacyLocalPath
          ? null
          : (legacyLocalPath ?? this.legacyLocalPath),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LibraryCoverAssetRef &&
        other.assetId == assetId &&
        other.revision == revision &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(assetId, revision, kind);

  static bool _hasText(String? value) => value?.trim().isNotEmpty == true;
}

abstract final class LibraryCoverAssetIds {
  static String source({required String ownerType, required String ownerId}) {
    return '${ownerType.trim()}/${ownerId.trim()}/source';
  }

  static String custom({required String ownerType, required String ownerId}) {
    return '${ownerType.trim()}/${ownerId.trim()}/custom';
  }
}
