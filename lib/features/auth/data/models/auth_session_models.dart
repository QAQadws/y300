import 'package:y300/core/utils/parse_utils.dart';

/// 会话快照，来自 profile 接口可稳定获取的最小字段集。
class SessionInfo {
  SessionInfo({
    required this.uid,
    required this.username,
    required this.formhash,
    required this.isLoggedIn,
  });

  final String uid;
  final String username;
  final String formhash;
  final bool isLoggedIn;

  factory SessionInfo.fromVariables(Map<String, dynamic> variables) {
    final uid = ParseUtils.asString(variables['member_uid']);
    return SessionInfo(
      uid: uid,
      username: ParseUtils.asString(variables['member_username']),
      formhash: ParseUtils.asString(variables['formhash']),
      isLoggedIn: uid.isNotEmpty && uid != '0',
    );
  }
}
