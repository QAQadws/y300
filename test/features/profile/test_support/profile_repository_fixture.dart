import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final class ProfileRepositoryFixture implements ForumUserProfileRepository {
  final queries = <ForumUserProfileQuery>[];
  @override
  final capabilities = ForumUserProfileSourceCapabilities(
    values: DataCapabilitySet.from(
      supported: [
        ForumUserProfileCapability.stableUserIdentity,
        ForumUserProfileCapability.userName,
      ],
    ),
  );

  @override
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    queries.add(query);
    return DataReadSuccess(
      data: ForumUserProfileData(
        metrics: const [],
        details: const [],
        identity: ProfileUserIdentity(
          userId: query.userId,
          displayName: 'fixture author',
        ),
      ),
      capabilities: ForumUserProfileReadCapabilities(
        values: capabilities.values,
      ),
      metadata: const DataReadMetadata.network(),
    );
  }
}
