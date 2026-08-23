import 'package:y300/features/profile/domain/models/current_user_profile_models.dart';
import 'package:y300/features/profile/domain/models/profile_user_identity.dart';

final class CurrentUserProfileUnauthorizedException implements Exception {
  const CurrentUserProfileUnauthorizedException();

  @override
  String toString() => 'Current user profile is not authenticated.';
}

final class CurrentUserProfileApiMapper {
  const CurrentUserProfileApiMapper();

  CurrentUserProfileData mapVariables(Map<String, dynamic> variables) {
    final memberUserId = _requiredAuthenticationIdentity(
      variables['member_uid'],
    );
    final rawSpace = variables['space'];
    if (rawSpace is! Map) {
      throw const FormatException('Current user profile space is missing.');
    }
    final space = Map<String, dynamic>.from(rawSpace);
    final spaceUserId = _optionalIdentity(space['uid']);
    if (spaceUserId != null && spaceUserId != memberUserId) {
      throw const FormatException('Current user profile identity mismatch.');
    }

    final memberName = _optionalText(variables['member_username']);
    final spaceName = _optionalText(space['username']);
    if (memberName != null && spaceName != null && memberName != spaceName) {
      throw const FormatException('Current user profile name mismatch.');
    }
    final displayName = spaceName ?? memberName;
    if (displayName == null) {
      throw const FormatException('Current user profile name is missing.');
    }

    return CurrentUserProfileData(
      identity: ProfileUserIdentity(
        userId: memberUserId,
        displayName: displayName,
      ),
      avatarUrl: _optionalText(variables['member_avatar']),
      groupId: _optionalIdentity(variables['groupid']),
      creditTotal: _optionalInteger(space, 'credits'),
      postCount: _optionalInteger(space, 'posts', nonNegative: true),
      threadCount: _optionalInteger(space, 'threads', nonNegative: true),
    );
  }

  String _requiredAuthenticationIdentity(Object? value) {
    final identity = _optionalIdentity(value);
    if (identity == null || identity == '0') {
      throw const CurrentUserProfileUnauthorizedException();
    }
    return identity;
  }

  String? _optionalIdentity(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String && value is! int) {
      throw const FormatException('Profile identity has an invalid type.');
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _optionalText(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw const FormatException('Profile text has an invalid type.');
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  int? _optionalInteger(
    Map<String, dynamic> values,
    String key, {
    bool nonNegative = false,
  }) {
    if (!values.containsKey(key) || values[key] == null) {
      return null;
    }
    final value = values[key];
    final parsed = switch (value) {
      int number => number,
      String text when RegExp(r'^-?\d+$').hasMatch(text.trim()) =>
        int.tryParse(text.trim()),
      _ => null,
    };
    if (parsed == null || (nonNegative && parsed < 0)) {
      throw FormatException('Profile $key is invalid.');
    }
    return parsed;
  }
}
