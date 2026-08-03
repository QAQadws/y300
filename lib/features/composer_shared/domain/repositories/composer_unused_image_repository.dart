import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';

abstract interface class ComposerUnusedImageRepository {
  Future<ApiResult<List<ComposerUnusedImage>>> loadUnusedImages();

  Future<ApiResult<ComposerUnusedImageDeleteResult>> deleteUnusedImage(
    String aid,
  );
}
