import 'package:y300/core/network/api_result.dart';

final class ComposerUnusedImage {
  const ComposerUnusedImage({
    required this.aid,
    required this.thumbnailUri,
    this.fileName = '',
    this.description = '',
  });

  final String aid;
  final Uri thumbnailUri;
  final String fileName;
  final String description;
}

enum ComposerUnusedImageDeleteOutcome { deleted, notDeleted, unconfirmed }

final class ComposerUnusedImageDeleteResult {
  const ComposerUnusedImageDeleteResult({
    required this.aid,
    required this.outcome,
    this.deletedCount,
  });

  final String aid;
  final ComposerUnusedImageDeleteOutcome outcome;
  final int? deletedCount;

  bool get deleted => outcome == ComposerUnusedImageDeleteOutcome.deleted;
}

typedef ComposerFormhashLoader = Future<ApiResult<String>> Function();
