import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/favorites/data/mappers/favorite_directory_api_mappers.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';

final class DiscuzFavoriteForumDirectoryRepository
    implements FavoriteForumDirectoryRepository {
  const DiscuzFavoriteForumDirectoryRepository(
    this._apiClient, {
    FavoriteForumDirectoryApiMapper mapper =
        const FavoriteForumDirectoryApiMapper(),
  }) : _mapper = mapper;

  final ApiClient _apiClient;
  final FavoriteForumDirectoryApiMapper _mapper;

  @override
  FavoriteForumDirectorySourceCapabilities get capabilities =>
      _forumCapabilities;

  @override
  Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  load(
    FavoriteForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final result = await _apiClient.getParsed<FavoriteForumDirectoryData>(
      module: 'myfavforum',
      parser: (response) => _mapper.mapVariables(response.variables),
    );
    return switch (result) {
      ApiSuccess<FavoriteForumDirectoryData>(:final data) => DataReadSuccess(
        data: data,
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      ),
      ApiFailure<FavoriteForumDirectoryData>(:final error) =>
        dataReadFailureFromApiError(error),
    };
  }
}

final class DiscuzFavoriteThreadDirectoryRepository
    implements FavoriteThreadDirectoryRepository {
  const DiscuzFavoriteThreadDirectoryRepository(
    this._apiClient, {
    FavoriteThreadDirectoryApiMapper mapper =
        const FavoriteThreadDirectoryApiMapper(),
  }) : _mapper = mapper;

  final ApiClient _apiClient;
  final FavoriteThreadDirectoryApiMapper _mapper;

  @override
  FavoriteThreadDirectorySourceCapabilities get capabilities =>
      _threadCapabilities;

  @override
  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  load(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    if (query.page < 1) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'favorite_thread_directory_query_invalid',
        diagnosticMessage: 'Favorite thread directory query is invalid.',
      );
    }
    final result = await _apiClient.getParsed<FavoriteThreadDirectoryData>(
      module: 'myfavthread',
      queryParameters: <String, dynamic>{'version': '4', 'page': query.page},
      parser: (response) =>
          _mapper.mapVariables(response.variables, requestedPage: query.page),
    );
    return switch (result) {
      ApiSuccess<FavoriteThreadDirectoryData>(:final data) => DataReadSuccess(
        data: data,
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      ),
      ApiFailure<FavoriteThreadDirectoryData>(:final error) =>
        dataReadFailureFromApiError(error),
    };
  }
}

final favoriteForumDirectoryRepositoryProvider =
    Provider<FavoriteForumDirectoryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).favoriteForumDirectory!;
    });

final favoriteThreadDirectoryRepositoryProvider =
    Provider<FavoriteThreadDirectoryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).favoriteThreadDirectory!;
    });

final _forumCapabilities = FavoriteForumDirectorySourceCapabilities(
  values: DataCapabilitySet<FavoriteForumDirectoryCapability>.supported(
    FavoriteForumDirectoryCapability.values,
  ),
);

final _threadCapabilities = FavoriteThreadDirectorySourceCapabilities(
  values: DataCapabilitySet<FavoriteThreadDirectoryCapability>.supported(
    FavoriteThreadDirectoryCapability.values,
  ),
  paginationPrecision: PaginationPrecision.exact,
);
