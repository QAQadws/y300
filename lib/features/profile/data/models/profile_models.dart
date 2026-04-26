import 'package:y300/core/utils/parse_utils.dart';

class ProfileData {
  ProfileData({
    required this.uid,
    required this.username,
    required this.avatar,
    required this.groupId,
    required this.credits,
    required this.posts,
    required this.threads,
    required this.formhash,
  });

  final String uid;
  final String username;
  final String avatar;
  final String groupId;
  final int credits;
  final int posts;
  final int threads;
  final String formhash;

  factory ProfileData.fromVariables(JsonMap variables) {
    final space = ParseUtils.asMap(variables['space']);
    return ProfileData(
      uid: ParseUtils.asString(
        space['uid'],
        fallback: ParseUtils.asString(variables['member_uid']),
      ),
      username: ParseUtils.asString(
        space['username'],
        fallback: ParseUtils.asString(variables['member_username']),
      ),
      avatar: ParseUtils.asString(variables['member_avatar']),
      groupId: ParseUtils.asString(variables['groupid']),
      credits: ParseUtils.asInt(space['credits']),
      posts: ParseUtils.asInt(space['posts']),
      threads: ParseUtils.asInt(space['threads']),
      formhash: ParseUtils.asString(variables['formhash']),
    );
  }
}
