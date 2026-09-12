import 'package:yamibo_forum_client/yamibo_forum_client.dart';

final blogConfig = ForumClientConfig(
  siteOrigin: Uri.parse('https://example.test'),
  apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
  userAgent: 'mobile-test',
  desktopUserAgent: 'desktop-test',
);

/// Reduced, self-contained markup from Discuz X3.5 touch/home templates.
/// No private user content, cookies, or live network requests are required.
String blogFeed({
  String view = 'all',
  String order = 'dateline',
  String? owner,
  String? category,
  String? personalCategory,
  int page = 1,
  int pages = 1,
  bool empty = false,
}) {
  final context =
      'home.php?mod=space&do=blog&view=$view&order=$order'
      '${owner == null ? '' : '&uid=$owner'}'
      '${category == null ? '' : '&catid=$category'}'
      '${personalCategory == null ? '' : '&classid=$personalCategory'}';
  return '''
<div class="dhnv"><a class="mon" href="$context">Feed</a></div>
<div id="dhnavs_li"><ul>
  ${view == 'all' ? '<li class="mon"><a href="$context">Order</a></li>' : ''}
  ${personalCategory == null ? '' : '<li class="mon"><a href="$context">Personal category</a></li>'}
  ${view == 'all' ? '<li><a href="home.php?mod=space&do=blog&view=all&catid=8">Stories</a></li>' : ''}
</ul></div>
<div class="threadlist"><ul>
${empty ? '' : '''<li class="list">
  <div class="threadlist_top"><a class="avatar"><img src="/avatar.png"></a>
    <div class="muser"><h3><a href="home.php?mod=space&uid=101&do=profile">Author</a></h3>
      <div class="mtime"><span>2026-09-12</span></div></div></div>
  <a href="home.php?mod=space&uid=101&do=blog&id=11">
    <div class="threadlist_tit">Title &amp; punctuation</div>
    <div class="threadlist_mes">An excerpt</div>
  </a></li>'''}
</ul></div>
${blogPager(context: context, page: page, pages: pages)}
''';
}

String blogPager({required String context, int page = 1, int pages = 1}) =>
    pages == 1
    ? ''
    : '''
<div class="pg">
  ${page > 1 ? '<a class="prev" href="$context&page=${page - 1}">Previous</a>' : ''}
  <strong>$page</strong><label><span> / $pages 页</span></label>
  ${page < pages ? '<a class="nxt" href="$context&page=${page + 1}">Next</a>' : ''}
</div>
''';

String blogArticle({
  int page = 1,
  int pages = 1,
  bool commentsOpen = true,
  bool anonymous = false,
  bool editOnly = false,
  String commentId = '5',
}) =>
    '''
<div class="viewthread">
  <div class="view_tit">Article title</div>
  <div class="plc">
    <div class="avatar"><img src="/owner.png"></div>
    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=101">Author</a></li>
      <li class="mtime"><span class="y"><i class="dm-eye"></i><em>100</em><i class="dm-chat-s"></i><em>40</em></span>Today</li></ul>
    <div class="message"><p>Real <b>rich text</b> and <img src="/image.png"></p></div>
    <div class="threadlist_foot"><a href="${editOnly ? 'home.php?mod=spacecp&ac=blog&op=edit&blogid=11' : 'home.php?mod=spacecp&ac=favorite&type=blog&id=11'}">Action</a></div>
  </div>
  <div class="doing_list_box"><ul>
    <li id="comment_${commentId}_li" class="doing_list_li list">
      <div class="threadlist_top"><a class="avatar"><img src="/comment.png"></a>
        <div class="muser"><h3>${anonymous ? 'Anonymous' : '<a href="home.php?mod=space&uid=102&do=profile">Reader</a>'}</h3>
          <div class="mtime"><span>Today</span></div></div></div>
      <div class="do_comment">A <b>comment</b></div>
    </li>
  </ul></div>
  ${commentsOpen ? '''<form id="quickcommentform_11" action="home.php?mod=spacecp&ac=comment" method="post">
    <textarea name="message"></textarea><input name="id" value="11"><input name="idtype" value="blogid">
    <input name="formhash" value="fixturehash"><input name="commentsubmit" value="true">
  </form>''' : ''}
  ${blogPager(context: 'home.php?mod=space&uid=101&do=blog&id=11', page: page, pages: pages)}
</div>
''';

class BlogFixtureNetwork implements ForumClientNetwork {
  BlogFixtureNetwork(this.body, {this.beforeResponse});
  final Object? body;
  final void Function()? beforeResponse;
  final requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    beforeResponse?.call();
    return ForumTransportSuccess(
      ForumResponse(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}
