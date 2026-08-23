import 'package:y300/features/profile/domain/models/profile_user_identity.dart';

enum ForumUserProfileView { public, self }

final class ForumUserProfileQuery {
  const ForumUserProfileQuery({
    required this.userId,
    this.view = ForumUserProfileView.public,
  });

  final String userId;
  final ForumUserProfileView view;

  @override
  bool operator ==(Object other) {
    return other is ForumUserProfileQuery &&
        other.userId == userId &&
        other.view == view;
  }

  @override
  int get hashCode => Object.hash(userId, view);
}

final class ForumUserProfileData {
  const ForumUserProfileData({
    required this.identity,
    required this.metrics,
    required this.details,
    this.avatarUrl,
    this.coverUrl,
    this.signatureHtml,
  });

  final ProfileUserIdentity identity;
  final String? avatarUrl;
  final String? coverUrl;
  final String? signatureHtml;
  final List<ForumUserProfileMetric> metrics;
  final List<ForumUserProfileDetail> details;
}

final class ForumUserProfileMetric {
  const ForumUserProfileMetric({required this.label, required this.value});

  final String label;
  final String value;
}

final class ForumUserProfileDetail {
  const ForumUserProfileDetail({required this.label, required this.value});

  final String label;
  final String value;
}
