import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/discuz_response.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/profile/data/repositories/profile_repository.dart';

abstract class ForumFavoriteRepository {
  Future<ApiResult<ForumFavoriteMutationResult>> favoriteForum({
    required String fid,
  });

  Future<ApiResult<ForumFavoriteMutationResult>> unfavoriteForum({
    required String favid,
  });
}

class DefaultForumFavoriteRepository implements ForumFavoriteRepository {
  DefaultForumFavoriteRepository({
    required ApiClient apiClient,
    required ProfileRepository profileRepository,
  }) : _apiClient = apiClient,
       _profileRepository = profileRepository;

  final ApiClient _apiClient;
  final ProfileRepository _profileRepository;
  @override
  Future<ApiResult<ForumFavoriteMutationResult>> favoriteForum({
    required String fid,
  }) async {
    final normalizedFid = fid.trim();
    if (normalizedFid.isEmpty) {
      return const ApiFailure<ForumFavoriteMutationResult>(
        ApiError(type: ApiErrorType.business, message: '版块 fid 不能为空'),
      );
    }

    final formhashResult = await _loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<ForumFavoriteMutationResult>(error);
    }
    final formhash = (formhashResult as ApiSuccess<String>).data;

    final response = await _apiClient.postDiscuzForm(
      module: 'favforum',
      queryParameters: const <String, dynamic>{'version': '4'},
      data: <String, String>{
        'formhash': formhash,
        'id': normalizedFid,
        'favoritesubmit': '1',
      },
    );
    return response.when(
      success: (data) => _mapFavoriteMutationResponse(data),
      failure: ApiFailure.new,
    );
  }

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> unfavoriteForum({
    required String favid,
  }) async {
    final normalizedFavid = favid.trim();
    if (normalizedFavid.isEmpty) {
      return const ApiFailure<ForumFavoriteMutationResult>(
        ApiError(type: ApiErrorType.business, message: '收藏 favid 不能为空'),
      );
    }

    final formhashResult = await _loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<ForumFavoriteMutationResult>(error);
    }
    final formhash = (formhashResult as ApiSuccess<String>).data;

    final response = await _apiClient.postDiscuzForm(
      module: 'favthread',
      queryParameters: <String, dynamic>{
        'version': '4',
        'op': 'delete',
        'favid': normalizedFavid,
      },
      data: <String, String>{'formhash': formhash, 'deletesubmit': 'true'},
    );
    return response.when(
      success: (data) => _mapUnfavoriteMutationResponse(data),
      failure: ApiFailure.new,
    );
  }

  Future<ApiResult<String>> _loadFormhash() async {
    final profile = await _profileRepository.getProfile();
    return profile.when(
      success: (data) {
        final formhash = data.formhash.trim();
        if (formhash.isEmpty) {
          return const ApiFailure<String>(
            ApiError(
              type: ApiErrorType.business,
              message: 'formhash 为空，无法提交版块收藏操作',
            ),
          );
        }
        return ApiSuccess<String>(formhash);
      },
      failure: (error) => ApiFailure<String>(
        ApiError(
          type: error.type,
          message: '获取 formhash 失败：${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      ),
    );
  }

  ApiResult<ForumFavoriteMutationResult> _mapFavoriteMutationResponse(
    DiscuzResponse response,
  ) {
    final message = _readMessage(response, fallback: '收藏结果未知');
    final code = _readCode(response).toLowerCase();
    final loweredMessage = message.toLowerCase();
    final alreadyApplied = _isAlreadyFavorited(code, loweredMessage);
    final success =
        alreadyApplied ||
        code.contains('success') ||
        code.contains('succeed') ||
        code == 'favorite_do_success' ||
        loweredMessage.contains('成功');
    if (!success) {
      return ApiFailure<ForumFavoriteMutationResult>(
        ApiError(
          type: ApiErrorType.business,
          message: message,
          code: _readCode(response),
          raw: response.message,
        ),
      );
    }
    return ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(
        message: message,
        alreadyApplied: alreadyApplied,
        code: alreadyApplied
            ? ForumFavoriteMutationCode.alreadyApplied
            : ForumFavoriteMutationCode.applied,
      ),
    );
  }

  ApiResult<ForumFavoriteMutationResult> _mapUnfavoriteMutationResponse(
    DiscuzResponse response,
  ) {
    final message = _readMessage(response, fallback: '取消收藏结果未知');
    final code = _readCode(response).toLowerCase();
    final loweredMessage = message.toLowerCase();
    final alreadyApplied = _isAlreadyUnfavorited(code, loweredMessage);
    final success =
        alreadyApplied ||
        code.contains('success') ||
        code.contains('succeed') ||
        code == 'do_success' ||
        loweredMessage.contains('成功');
    if (!success) {
      return ApiFailure<ForumFavoriteMutationResult>(
        ApiError(
          type: ApiErrorType.business,
          message: message,
          code: _readCode(response),
          raw: response.message,
        ),
      );
    }
    return ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(
        message: message,
        alreadyApplied: alreadyApplied,
        code: alreadyApplied
            ? ForumFavoriteMutationCode.alreadyApplied
            : ForumFavoriteMutationCode.applied,
      ),
    );
  }

  String _readMessage(DiscuzResponse response, {required String fallback}) {
    final messageNode = response.message;
    return ParseUtils.asString(
      messageNode?['messagestr'],
      fallback: ParseUtils.asString(
        messageNode?['messageval'],
        fallback: fallback,
      ),
    );
  }

  String _readCode(DiscuzResponse response) {
    return ParseUtils.asString(response.message?['messageval'], fallback: '');
  }

  bool _isAlreadyFavorited(String loweredCode, String loweredMessage) {
    return loweredCode.contains('favorite_repeat') ||
        loweredCode.contains('favorite_already') ||
        loweredCode.contains('favorite_exists') ||
        loweredCode.contains('already') ||
        loweredCode.contains('exist') ||
        loweredMessage.contains('已收藏') ||
        loweredMessage.contains('已经收藏') ||
        loweredMessage.contains('收藏过');
  }

  bool _isAlreadyUnfavorited(String loweredCode, String loweredMessage) {
    return loweredCode.contains('favorite_does_not_exist') ||
        loweredCode.contains('not_exist') ||
        loweredCode.contains('noexist') ||
        loweredCode.contains('notfound') ||
        loweredMessage.contains('未收藏') ||
        loweredMessage.contains('不存在') ||
        loweredMessage.contains('没有收藏');
  }
}

final forumFavoriteRepositoryProvider = Provider<ForumFavoriteRepository>((
  ref,
) {
  return DefaultForumFavoriteRepository(
    apiClient: ref.watch(apiClientProvider),
    profileRepository: ref.watch(profileRepositoryProvider),
  );
});
