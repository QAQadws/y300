import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/discuz_ajax_cdata_parser.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/composer_shared/data/services/composer_unused_image_parser.dart';
import 'package:y300/features/composer_shared/data/services/composer_unused_image_remote_data_source.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_unused_image_repository.dart';

final class DiscuzComposerUnusedImageRepository
    implements ComposerUnusedImageRepository {
  const DiscuzComposerUnusedImageRepository({
    required ComposerUnusedImageRemoteDataSource remoteDataSource,
    required YamiboSessionStore sessionStore,
    required ComposerFormhashLoader loadFormhash,
    this.parser = const ComposerUnusedImageParser(),
    this.cdataParser = const DiscuzAjaxCdataParser(),
  }) : _remoteDataSource = remoteDataSource,
       _sessionStore = sessionStore,
       _loadFormhash = loadFormhash;

  final ComposerUnusedImageRemoteDataSource _remoteDataSource;
  final YamiboSessionStore _sessionStore;
  final ComposerFormhashLoader _loadFormhash;
  final ComposerUnusedImageParser parser;
  final DiscuzAjaxCdataParser cdataParser;

  @override
  Future<ApiResult<List<ComposerUnusedImage>>> loadUnusedImages() async {
    final uri = Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/forum.php',
      queryParameters: const <String, String>{
        'mod': 'ajax',
        'action': 'imagelist',
        'posttime': '0',
      },
    );
    final result = await _remoteDataSource.load(uri);
    if (result case ApiFailure<ComposerUnusedImageRemoteDocument>(
      :final error,
    )) {
      return ApiFailure(error);
    }
    final document = result.dataOrNull!;
    try {
      final images = parser.parse(
        body: document.body,
        sourceUri: document.sourceUri,
        hasConfirmedLoggedInSession: _hasConfirmedLoggedInSession(),
      );
      return ApiSuccess(images);
    } on FormatException catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          code: 'unused_image_catalog_invalid',
          message: error.message,
        ),
      );
    }
  }

  @override
  Future<ApiResult<ComposerUnusedImageDeleteResult>> deleteUnusedImage(
    String aid,
  ) async {
    final normalizedAid = aid.trim();
    final parsedAid = int.tryParse(normalizedAid);
    if (parsedAid == null || parsedAid <= 0) {
      return const ApiFailure(
        ApiError(
          type: ApiErrorType.business,
          code: 'unused_image_aid_invalid',
          message: 'Invalid attachment aid',
        ),
      );
    }
    final formhashResult = await _loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure(error);
    }
    final formhash = formhashResult.dataOrNull!.trim();
    if (formhash.isEmpty) {
      return const ApiFailure(
        ApiError(
          type: ApiErrorType.unauthorized,
          code: 'formhash_missing',
          message: 'Missing formhash',
        ),
      );
    }
    final uri = Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'ajax',
        'action': 'deleteattach',
        'inajax': 'yes',
        'formhash': formhash,
        'tid': '0',
        'pid': '0',
        'aids[]': normalizedAid,
      },
    );
    final result = await _remoteDataSource.delete(uri);
    if (result case ApiFailure<ComposerUnusedImageRemoteDocument>(
      :final error,
    )) {
      return ApiFailure(error);
    }
    final document = result.dataOrNull!;
    if (!_isExpectedDeleteResponseUri(document.sourceUri)) {
      return const ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          code: 'unused_image_delete_redirected',
          message: 'Unexpected attachment deletion response location',
        ),
      );
    }
    final count = cdataParser.extractInteger(document.body);
    if (count == null) {
      return ApiSuccess(
        ComposerUnusedImageDeleteResult(
          aid: normalizedAid,
          outcome: ComposerUnusedImageDeleteOutcome.unconfirmed,
        ),
      );
    }
    return ApiSuccess(
      ComposerUnusedImageDeleteResult(
        aid: normalizedAid,
        deletedCount: count,
        outcome: count > 0
            ? ComposerUnusedImageDeleteOutcome.deleted
            : ComposerUnusedImageDeleteOutcome.notDeleted,
      ),
    );
  }

  bool _isExpectedDeleteResponseUri(Uri sourceUri) {
    final siteUri = Uri.parse(AppConfig.siteBaseUrl);
    return sourceUri.scheme.toLowerCase() == siteUri.scheme.toLowerCase() &&
        sourceUri.host.toLowerCase() == siteUri.host.toLowerCase() &&
        sourceUri.port == siteUri.port &&
        sourceUri.path == '/forum.php' &&
        sourceUri.queryParameters['mod'] == 'ajax' &&
        sourceUri.queryParameters['action'] == 'deleteattach';
  }

  bool _hasConfirmedLoggedInSession() {
    final session = _sessionStore.readCurrent();
    final uid = int.tryParse(session?.uid.trim() ?? '');
    return session?.isLoggedIn == true && uid != null && uid > 0;
  }
}
