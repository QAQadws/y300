enum ForumWebViewPageKind { home, forumDisplay, threadDetail, search, other }

enum ForumWebViewSearchScope { forum, curForum }

class ForumThreadMenuSnapshot {
  const ForumThreadMenuSnapshot({
    this.authorOnlyUri,
    this.normalThreadUri,
    this.reverseOrderUri,
    this.normalOrderUri,
  });

  final Uri? authorOnlyUri;
  final Uri? normalThreadUri;
  final Uri? reverseOrderUri;
  final Uri? normalOrderUri;
}

class ForumThreadDocumentSnapshot {
  const ForumThreadDocumentSnapshot({
    required this.postCount,
    required this.menu,
    this.title,
    this.forumName,
    this.canonicalUri,
    this.firstPostImageUrl,
  });

  final String? title;
  final String? forumName;
  final Uri? canonicalUri;
  final String? firstPostImageUrl;
  final int postCount;
  final ForumThreadMenuSnapshot menu;

  bool get hasPostProof => postCount > 0 && (title?.trim().isNotEmpty ?? false);
}

class ForumThreadDetailMenuState {
  const ForumThreadDetailMenuState({
    required this.isAuthorOnly,
    required this.isReverseOrder,
    required this.authorOnlyUri,
    required this.normalThreadUri,
    required this.reverseOrderUri,
    required this.normalOrderUri,
  });

  final bool isAuthorOnly;
  final bool isReverseOrder;
  final Uri? authorOnlyUri;
  final Uri? normalThreadUri;
  final Uri reverseOrderUri;
  final Uri normalOrderUri;
}
