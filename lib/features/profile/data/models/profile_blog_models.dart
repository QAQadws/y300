enum ProfileBlogView {
  friends('好友的日志', 'we'),
  mine('我的日志', 'me'),
  all('随便看看', 'all');

  const ProfileBlogView(this.label, this.queryValue);

  final String label;
  final String queryValue;
}

enum ProfileBlogOrder {
  latest('最新发表的日志', 'dateline'),
  hot('推荐阅读的日志', 'hot');

  const ProfileBlogOrder(this.label, this.queryValue);

  final String label;
  final String queryValue;
}

class ProfileBlogListPageData {
  const ProfileBlogListPageData({
    required this.title,
    required this.activeView,
    required this.activeOrder,
    required this.viewTabs,
    required this.orderTabs,
    required this.items,
    this.emptyMessage,
    this.pagination,
  });

  final String title;
  final ProfileBlogView activeView;
  final ProfileBlogOrder activeOrder;
  final List<ProfileBlogNavigationTab> viewTabs;
  final List<ProfileBlogNavigationTab> orderTabs;
  final List<ProfileBlogListItem> items;
  final String? emptyMessage;
  final ProfileBlogPagination? pagination;
}

class ProfileBlogNavigationTab {
  const ProfileBlogNavigationTab({
    required this.label,
    required this.url,
    required this.isActive,
  });

  final String label;
  final String url;
  final bool isActive;
}

class ProfileBlogListItem {
  const ProfileBlogListItem({
    required this.id,
    required this.uid,
    required this.title,
    required this.excerpt,
    required this.author,
    required this.authorUrl,
    required this.avatarUrl,
    required this.dateline,
    required this.url,
  });

  final String id;
  final String uid;
  final String title;
  final String excerpt;
  final String author;
  final String? authorUrl;
  final String? avatarUrl;
  final String dateline;
  final String url;
}

class ProfileBlogPagination {
  const ProfileBlogPagination({
    required this.currentPage,
    required this.totalPages,
    this.nextUrl,
    this.multipageUrl,
  });

  final int currentPage;
  final int totalPages;
  final String? nextUrl;
  final String? multipageUrl;
}

class ProfileBlogDetailData {
  const ProfileBlogDetailData({
    required this.id,
    required this.uid,
    required this.title,
    required this.author,
    required this.authorUrl,
    required this.avatarUrl,
    required this.dateline,
    required this.views,
    required this.commentsCount,
    required this.messageHtml,
    required this.actions,
    required this.comments,
    this.commentForm,
  });

  final String id;
  final String uid;
  final String title;
  final String author;
  final String? authorUrl;
  final String? avatarUrl;
  final String dateline;
  final int views;
  final int commentsCount;
  final String messageHtml;
  final List<ProfileBlogAction> actions;
  final List<ProfileBlogComment> comments;
  final ProfileBlogCommentForm? commentForm;
}

class ProfileBlogAction {
  const ProfileBlogAction({required this.label, required this.url});

  final String label;
  final String url;
}

class ProfileBlogComment {
  const ProfileBlogComment({
    required this.id,
    required this.author,
    required this.authorUrl,
    required this.avatarUrl,
    required this.dateline,
    required this.messageHtml,
    this.replyUrl,
  });

  final String id;
  final String author;
  final String? authorUrl;
  final String? avatarUrl;
  final String dateline;
  final String messageHtml;
  final String? replyUrl;
}

class ProfileBlogCommentForm {
  const ProfileBlogCommentForm({
    required this.actionUrl,
    required this.formhash,
    required this.blogId,
    required this.referer,
  });

  final String actionUrl;
  final String formhash;
  final String blogId;
  final String referer;
}
