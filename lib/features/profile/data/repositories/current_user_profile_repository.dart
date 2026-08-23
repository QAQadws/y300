import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/data/mappers/current_user_profile_api_mapper.dart';
import 'package:y300/features/profile/domain/models/current_user_profile_models.dart';
import 'package:y300/features/profile/domain/repositories/current_user_profile_repository.dart';

final class DiscuzCurrentUserProfileRepository
    implements CurrentUserProfileRepository {
  const DiscuzCurrentUserProfileRepository(
    this._apiClient, {
    CurrentUserProfileApiMapper mapper = const CurrentUserProfileApiMapper(),
  }) : _mapper = mapper;

  final ApiClient _apiClient;
  final CurrentUserProfileApiMapper _mapper;

  @override
  CurrentUserProfileSourceCapabilities get capabilities => _capabilities;

  @override
  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load(
    CurrentUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final result = await _apiClient.getDiscuz(module: 'profile');
    if (result case ApiFailure(:final error)) {
      return dataReadFailureFromApiError(error);
    }
    try {
      final data = _mapper.mapVariables(result.dataOrNull!.variables);
      return DataReadSuccess(
        data: data,
        capabilities: _readCapabilities(data),
        metadata: const DataReadMetadata.network(),
      );
    } on CurrentUserProfileUnauthorizedException {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'current_user_profile_unauthorized',
        diagnosticMessage: 'Current user profile is not authenticated.',
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'current_user_profile_parse_failed',
        diagnosticMessage: 'Current user profile response is invalid.',
      );
    }
  }

  CurrentUserProfileReadCapabilities _readCapabilities(
    CurrentUserProfileData data,
  ) {
    var values = _capabilities.values;
    values = _optional(
      values,
      CurrentUserProfileCapability.avatarReference,
      data.avatarUrl != null,
    );
    values = _optional(
      values,
      CurrentUserProfileCapability.groupIdentity,
      data.groupId != null,
    );
    values = _optional(
      values,
      CurrentUserProfileCapability.creditTotal,
      data.creditTotal != null,
    );
    values = _optional(
      values,
      CurrentUserProfileCapability.postCount,
      data.postCount != null,
    );
    values = _optional(
      values,
      CurrentUserProfileCapability.threadCount,
      data.threadCount != null,
    );
    return CurrentUserProfileReadCapabilities(values: values);
  }
}

DataCapabilitySet<CurrentUserProfileCapability> _optional(
  DataCapabilitySet<CurrentUserProfileCapability> values,
  CurrentUserProfileCapability capability,
  bool supported,
) {
  return values.withSupport(
    capability,
    supported
        ? DataCapabilitySupport.supported
        : DataCapabilitySupport.unsupported,
  );
}

final _capabilities = CurrentUserProfileSourceCapabilities(
  values: DataCapabilitySet<CurrentUserProfileCapability>.supported(
    CurrentUserProfileCapability.values,
  ),
);
