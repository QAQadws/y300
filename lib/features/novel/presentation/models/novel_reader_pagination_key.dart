import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Identity of one HTML-first pagination layout.
///
/// The dimensions are logical Flutter pixels rounded to integers at the
/// boundary. This keeps cache keys stable across harmless floating-point
/// layout noise while still invalidating when the usable viewport changes.
@immutable
class NovelReaderPaginationKey {
  const NovelReaderPaginationKey({
    required this.episodeId,
    required this.contentHash,
    required this.viewportWidthPx,
    required this.viewportHeightPx,
    required this.typographySignature,
    required this.themeSignature,
    required this.imageDimensionRevision,
    required this.rendererRevision,
  });

  final String episodeId;
  final String contentHash;
  final int viewportWidthPx;
  final int viewportHeightPx;
  final String typographySignature;
  final String themeSignature;
  final int imageDimensionRevision;
  final int rendererRevision;

  /// A stable cache identity. It is not a persistence or business ID.
  String get cacheIdentity => jsonEncode(<Object?>[
    episodeId,
    contentHash,
    viewportWidthPx,
    viewportHeightPx,
    typographySignature,
    themeSignature,
    imageDimensionRevision,
    rendererRevision,
  ]);

  /// A compact identity persisted with reading progress. It deliberately
  /// excludes the physical PageController and any generated page HTML.
  String get layoutFingerprint =>
      sha256.convert(utf8.encode(cacheIdentity)).toString();

  static int logicalPixels(double value) {
    if (!value.isFinite || value <= 0) {
      return 0;
    }
    return value.round();
  }

  @override
  bool operator ==(Object other) {
    return other is NovelReaderPaginationKey &&
        other.episodeId == episodeId &&
        other.contentHash == contentHash &&
        other.viewportWidthPx == viewportWidthPx &&
        other.viewportHeightPx == viewportHeightPx &&
        other.typographySignature == typographySignature &&
        other.themeSignature == themeSignature &&
        other.imageDimensionRevision == imageDimensionRevision &&
        other.rendererRevision == rendererRevision;
  }

  @override
  int get hashCode => Object.hash(
    episodeId,
    contentHash,
    viewportWidthPx,
    viewportHeightPx,
    typographySignature,
    themeSignature,
    imageDimensionRevision,
    rendererRevision,
  );
}
