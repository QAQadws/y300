import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/forum/data/mappers/forum_directory_api_mapper.dart';
import 'package:y300/features/forum/data/services/forum_directory_validator.dart';
import 'package:y300/features/forum/domain/models/forum_directory_models.dart';
import 'package:y300/features/forum/domain/repositories/forum_directory_repository.dart';

final class DiscuzForumDirectoryRepository implements ForumDirectoryRepository {
  DiscuzForumDirectoryRepository(
    this._apiClient, {
    ForumDirectoryApiMapper mapper = const ForumDirectoryApiMapper(),
  }) : _mapper = mapper;

  final ApiClient _apiClient;
  final ForumDirectoryApiMapper _mapper;

  @override
  ForumDirectorySourceCapabilities get capabilities => _apiCapabilities;

  @override
  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  load(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final result = await _apiClient.getParsed<ForumDirectoryData>(
      module: 'forumindex',
      parser: (response) => _mapper.mapVariables(response.variables),
    );
    return switch (result) {
      ApiSuccess<ForumDirectoryData>(:final data) => _toReadSuccess(data),
      ApiFailure<ForumDirectoryData>(:final error) =>
        dataReadFailureFromApiError(error),
    };
  }

  DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>
  _toReadSuccess(ForumDirectoryData data) {
    final validation = validateForumDirectory(data);
    if (validation != null) {
      return DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_directory_identity_invalid',
        diagnosticMessage: validation,
      );
    }
    return DataReadSuccess(
      data: data,
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

final _apiCapabilities = ForumDirectorySourceCapabilities(
  values: DataCapabilitySet<ForumDirectoryCapability>.supported(
    ForumDirectoryCapability.values,
  ),
);

final forumDirectoryApiRepositoryProvider = Provider<ForumDirectoryRepository>((
  ref,
) {
  return DiscuzForumDirectoryRepository(ref.watch(apiClientProvider));
});
