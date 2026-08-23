import 'package:y300/features/profile/domain/models/profile_user_identity.dart';

final class CurrentUserProfileQuery {
  const CurrentUserProfileQuery();
}

final class CurrentUserProfileData {
  const CurrentUserProfileData({
    required this.identity,
    this.avatarUrl,
    this.groupId,
    this.creditTotal,
    this.postCount,
    this.threadCount,
  });

  final ProfileUserIdentity identity;
  final String? avatarUrl;
  final String? groupId;
  final int? creditTotal;
  final int? postCount;
  final int? threadCount;
}
