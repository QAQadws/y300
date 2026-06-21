class UserProfileData {
  const UserProfileData({
    required this.uid,
    required this.username,
    required this.title,
    this.avatarUrl,
    this.coverUrl,
    this.signatureHtml,
    this.threadUrl,
    this.blogUrl,
    this.messageUrl,
    this.friendUrl,
    this.favoriteUrl,
    this.signUrl,
    this.settingsUrl,
    this.logoutUrl,
    this.actions = const <UserProfileAction>[],
    this.credits = const <UserProfileMetric>[],
    this.details = const <UserProfileDetailItem>[],
  });

  final String uid;
  final String username;
  final String title;
  final String? avatarUrl;
  final String? coverUrl;
  final String? signatureHtml;
  final String? threadUrl;
  final String? blogUrl;
  final String? messageUrl;
  final String? friendUrl;
  final String? favoriteUrl;
  final String? signUrl;
  final String? settingsUrl;
  final String? logoutUrl;
  final List<UserProfileAction> actions;
  final List<UserProfileMetric> credits;
  final List<UserProfileDetailItem> details;
}

class UserProfileMetric {
  const UserProfileMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class UserProfileDetailItem {
  const UserProfileDetailItem({required this.label, required this.value});

  final String label;
  final String value;
}

class UserProfileAction {
  const UserProfileAction({required this.label, required this.url});

  final String label;
  final String url;
}
