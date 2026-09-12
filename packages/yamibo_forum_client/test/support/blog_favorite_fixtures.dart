import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'blog_fixtures.dart';
import 'blog_operation_fixtures.dart';

// Reduced from touch/home/spacecp_favorite.htm and spacecp_favorite.php.
const blogFavoriteTarget = UserBlogFavoriteTarget(
  actorUserId: '101',
  ownerUserId: '101',
  blogId: '11',
);
String blogFavoriteForm({bool existing = false}) =>
    '''$blogOperationHeader
<div class="tip"><form method="post" id="favoriteform_${existing ? '55' : '11'}"
action="home.php?mod=spacecp&ac=favorite&type=blog&${existing ? 'op=delete&favid=55' : 'id=11&spaceuid=101'}&mobile=2">
<input type="hidden" name="${existing ? 'deletesubmit' : 'favoritesubmit'}" value="true">
<input type="hidden" name="referer" value="https://untrusted.test/return">
<input type="hidden" name="formhash" value="fixturehash">
${existing ? '' : '<textarea name="description">Server placeholder</textarea>'}
<input type="submit" name="${existing ? 'deletesubmitbtn' : 'favoritesubmit_btn'}" value="Confirm">
</form></div>''';

String blogFavoriteCallback({
  bool applied = true,
  String? destination,
  String values = "'id':'11','favid':'55'",
}) {
  final handler =
      '${applied ? 'succeedhandle' : 'errorhandle'}_y300_blog_favorite';
  final uri =
      destination ?? 'home.php?mod=space&uid=101&do=blog&id=11&mobile=2';
  return '''<?xml version="1.0"?><root><![CDATA[<script>if(typeof $handler=='function') {$handler(${applied ? "'$uri', " : ''}'private server message', {$values});}</script>]]></root>''';
}

class BlogFavoriteNetwork implements ForumClientNetwork {
  String article =
      '$blogOperationHeader${blogArticle().replaceFirst('type=blog&id=11', 'type=blog&id=11&spaceuid=101')}';
  String form = blogFavoriteForm();
  String existing = blogFavoriteForm(existing: true);
  String postBody = blogFavoriteCallback();
  Uri? responseUri;
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
        ? postBody
        : request.uri.queryParameters['mod'] == 'space'
        ? article
        : request.uri.queryParameters['op'] == 'delete'
        ? existing
        : form;
    return ForumTransportSuccess(
      ForumResponse(
        uri: responseUri ?? request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}
