import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client.dart';

import 'blog_fixtures.dart';

// Reduced from home/spacecp_blog.htm and its touch management forms. The site
// category placeholder deliberately matches category_showselect's empty value.
const blogOperationHeader =
    "<script>var STYLEID = '1', discuz_uid = '101';</script>";
const blogEditorHtml = '<p>原文 &amp; <b>bold</b></p><img src="/picture.png">';
String blogEditorForm({
  bool create = false,
  int visibility = 0,
  bool commentsEnabled = true,
  bool siteCategoryRequired = false,
  bool categories = true,
  bool feed = true,
  bool canCreateCategory = true,
  String owner = '101',
}) =>
    '''
$blogOperationHeader
<div id="pt"><a href="home.php?mod=space&uid=$owner&do=blog&id=11">Title</a></div>
<form id="ttHtmlEditor" method="post" enctype="multipart/form-data"
 action="home.php?mod=spacecp&ac=blog&blogid=${create ? '' : '11'}">
<input type="text" name="subject" value="Title &amp; text">
<textarea name="message">&lt;p&gt;原文 &amp;amp; &lt;b&gt;bold&lt;/b&gt;&lt;/p&gt;&lt;img src="/picture.png"&gt;</textarea>
${categories ? '''<select name="catid">${siteCategoryRequired ? '' : '<option value="">Select category</option>'}
  <option value="8">Stories</option><option value="9">-- Daily life</option></select>''' : ''}
<select name="classid"><option value="0">------</option><option value="3">My category</option>
  ${canCreateCategory ? '<option value="addoption">+ Create</option>' : ''}</select>
<input type="text" name="tag" value="one,two">
<select name="friend">${[for (var i = 0; i < 5; i++) '<option value="$i"${visibility == i ? ' selected' : ''}>Policy $i</option>'].join()}</select>
<input type="checkbox" name="noreply" value="1"${commentsEnabled ? '' : ' checked'}>
<input type="text" name="password" value="fixture.password">
<textarea name="target_names">Reader One Reader Two</textarea>
<input type="text" name="hot" value="7">
${feed ? '<input type="checkbox" name="makefeed" value="1" checked>' : ''}
<select name="selectgroup"><option value="">Group</option></select>
<select name="savealbumid"><option value="0">Album</option></select>
<input type="text" name="newalbum"><select name="view_albumid"><option value="0">Album</option></select>
<button type="submit" id="issuance">Save</button>
<input type="hidden" name="blogsubmit" value="true">
<input type="hidden" name="formhash" value="fixturehash">
</form>
''';

String blogActionForm(UserBlogAction action) {
  final deleting = action == UserBlogAction.delete;
  return '''$blogOperationHeader
<div class="tip"><form method="post" action="home.php?mod=spacecp&ac=blog&op=${deleting ? 'delete' : 'stick'}&blogid=11">
<input type="hidden" name="referer" value="https://external.test/untrusted">
<input type="hidden" name="${deleting ? 'deletesubmit' : 'sticksubmit'}" value="true">
${deleting ? '' : '<input type="hidden" name="stickflag" value="${action == UserBlogAction.pin ? '1' : '0'}">'}
<input type="hidden" name="formhash" value="fixturehash">
<button type="submit" name="btnsubmit" value="true" class="formdialog button z">Confirm</button>
</form></div>''';
}

String blogManagedArticle({bool deletionAllowed = true}) =>
    '$blogOperationHeader${blogArticle().replaceFirst('</div>\n  </div>\n  <div class="doing_list_box">', '''${deletionAllowed ? '<a href="home.php?mod=spacecp&ac=blog&op=delete&blogid=11&handlekey=delbloghk_11">Delete</a>' : ''}</div>
  </div>
  <div class="doing_list_box">''')}';

String blogOperationCallback(
  UserBlogAction action, {
  bool success = true,
  String? destination,
}) {
  final editor =
      action == UserBlogAction.create || action == UserBlogAction.edit;
  final handle = editor ? 'y300_blog_editor' : 'y300_blog_action';
  final name = '${success ? 'succeedhandle' : 'errorhandle'}_$handle';
  final url =
      destination ??
      'home.php?mod=space&uid=101&do=blog&${action == UserBlogAction.delete ? 'view=me' : 'quickforward=1&id=${action == UserBlogAction.create ? '12' : '11'}'}';
  return '''<?xml version="1.0"?><root><![CDATA[<script>if(typeof $name=='function') {$name(${success ? "'$url', " : ''}'private server message', {});}</script>]]></root>''';
}

UserBlogTarget blogOperationTarget(UserBlogAction action) => UserBlogTarget(
  actorUserId: '101',
  ownerUserId: '101',
  action: action,
  blogId: action == UserBlogAction.create ? null : '11',
);

Future<void> loginBlogActor(MemoryForumSessionStore store, String actor) =>
    store.merge(
      ForumSessionSnapshot(
        isLoggedIn: true,
        userId: actor,
        username: 'Fixture',
        formhash: 'fixturehash',
        updatedAt: DateTime.now(),
        source: 'test',
      ),
    );

UserBlogEditorSubmission blogEditorSubmission(
  UserBlogEditorPreparation ready, {
  String subject = 'Updated 标题',
  String? bodyHtml,
  String? siteCategory,
  String personalCategory = '0',
  String? newCategory,
  bool? feed,
  ForumRequestCancellation? cancellation,
}) => UserBlogEditorSubmission(
  preparation: ready,
  actorUserId: '101',
  subject: subject,
  bodyHtml: bodyHtml ?? ready.bodyHtml,
  tags: 'updated,tag',
  siteCategoryId: siteCategory ?? ready.siteCategoryId,
  personalCategoryId: personalCategory,
  newPersonalCategory: newCategory,
  publishFeed: feed ?? ready.publishFeed,
  cancellation: cancellation,
);

class BlogOperationNetwork implements ForumClientNetwork {
  BlogOperationNetwork(this.action);
  final UserBlogAction action;
  String? editor;
  String? article;
  String? actionForm;
  String? postBody;
  Uri? responseUri;
  int statusCode = 200;
  FutureOr<void> Function(ForumRequest)? onRequest;
  final requests = <ForumRequest>[];
  List<ForumRequest> get posts =>
      requests.where((r) => r.method == ForumRequestMethod.post).toList();

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    await onRequest?.call(request);
    final body = request.method == ForumRequestMethod.post
        ? postBody ?? blogOperationCallback(action)
        : request.uri.queryParameters['mod'] == 'space'
        ? article ?? blogManagedArticle()
        : action == UserBlogAction.create || action == UserBlogAction.edit
        ? editor ?? blogEditorForm(create: action == UserBlogAction.create)
        : actionForm ?? blogActionForm(action);
    return ForumTransportSuccess(
      ForumResponse(
        uri: responseUri ?? request.uri,
        statusCode: statusCode,
        headers: const {},
        body: body,
      ),
    );
  }
}
