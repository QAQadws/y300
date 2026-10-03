import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final class ProfileRepositoryFixture implements ForumUserProfileRepository {
  ProfileRepositoryFixture({this.actions = const []});

  final List<ForumUserProfileActionKind> actions;
  final queries = <ForumUserProfileQuery>[];
  @override
  ForumUserProfileSourceCapabilities get capabilities =>
      ForumUserProfileSourceCapabilities(
        values: DataCapabilitySet.from(
          supported: [
            ForumUserProfileCapability.stableUserIdentity,
            ForumUserProfileCapability.userName,
            if (actions.isNotEmpty) ForumUserProfileCapability.orderedActions,
          ],
        ),
      );

  @override
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    return DataReadSuccess(
      data: ForumUserProfileData(
        viewerUserId: query.viewerUserId,
        actions: actions,
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
