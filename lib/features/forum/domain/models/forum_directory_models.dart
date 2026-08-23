final class ForumDirectoryQuery {
  const ForumDirectoryQuery();
}

final class ForumDirectoryData {
  const ForumDirectoryData({required this.sections});

  final List<ForumDirectorySection> sections;
}

enum ForumDirectorySectionKind { regular, uncategorized }

final class ForumDirectorySection {
  const ForumDirectorySection({
    required this.identity,
    required this.title,
    required this.forums,
    this.kind = ForumDirectorySectionKind.regular,
  });

  final String identity;
  final String title;
  final List<ForumDirectoryForum> forums;
  final ForumDirectorySectionKind kind;
}

final class ForumDirectoryForum {
  const ForumDirectoryForum({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
    this.children = const <ForumDirectoryForum>[],
  });

  final String fid;
  final String title;
  final String description;
  final int? todayPosts;
  final List<ForumDirectoryForum> children;
}
