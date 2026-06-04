enum ForumWebViewPageKind {
  home,
  forumDisplay,
  threadDetail,
  search,
  other,
}

enum ForumWebViewSearchScope {
  forum,
  curForum,
}

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
