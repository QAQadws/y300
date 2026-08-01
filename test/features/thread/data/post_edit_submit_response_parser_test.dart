import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/services/post_edit_submit_response_parser.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';

void main() {
  const parser = PostEditSubmitResponseParser();
  final target = PostEditTarget(
    editUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&tid=20&pid=30',
    ),
    fid: '5',
    tid: '20',
    pid: '30',
    page: 1,
    isFirstPost: false,
  );

  test('confirms a same-post redirect', () {
    final result = parser.parse(
      responseUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=20&pid=30#pid30',
      ),
      body: '',
      target: target,
    );

    expect(result.kind, PostEditSubmitResponseKind.confirmedSuccess);
  });

  test('resolves a relative same-post redirect in the response body', () {
    final result = parser.parse(
      responseUri: target.editUri,
      body:
          '<a href="forum.php?mod=viewthread&amp;tid=20&amp;pid=30#pid30">继续</a>',
      target: target,
    );

    expect(result.kind, PostEditSubmitResponseKind.confirmedSuccess);
  });

  test('confirms only a stable success structure with the target ids', () {
    final result = parser.parse(
      responseUri: target.editUri,
      body: '<root><message>post_edit_succeed tid=20 pid=30</message></root>',
      target: target,
    );

    expect(result.kind, PostEditSubmitResponseKind.confirmedSuccess);
  });

  test('keeps generic success text and unknown HTML ambiguous', () {
    final result = parser.parse(
      responseUri: target.editUri,
      body: '<html><body>保存成功</body></html>',
      target: target,
    );

    expect(result.kind, PostEditSubmitResponseKind.ambiguous);
  });

  test('classifies authentication, permission and formhash failures', () {
    expect(
      parser
          .parse(
            responseUri: Uri.parse(
              'https://bbs.yamibo.com/member.php?mod=logging',
            ),
            body: '<form id="loginform"></form>',
            target: target,
          )
          .kind,
      PostEditSubmitResponseKind.authenticationFailure,
    );
    expect(
      parser
          .parse(
            responseUri: target.editUri,
            body: '<div class="error">nopermission</div>',
            target: target,
          )
          .kind,
      PostEditSubmitResponseKind.permissionFailure,
    );
    expect(
      parser
          .parse(
            responseUri: target.editUri,
            body: 'formhash_expired',
            target: target,
          )
          .kind,
      PostEditSubmitResponseKind.formExpired,
    );
  });

  test('deleted posts remain a business failure with a stable reason', () {
    final result = parser.parse(
      responseUri: target.editUri,
      body: '<div class="error">该帖子不存在或已删除</div>',
      target: target,
    );

    expect(result.kind, PostEditSubmitResponseKind.businessFailure);
    expect(result.detail, 'post_deleted');
  });

  test('does not accept a redirect to another post', () {
    final result = parser.parse(
      responseUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=21&pid=31#pid31',
      ),
      body: '<message>post_edit_succeed tid=20 pid=30</message>',
      target: target,
    );

    expect(result.kind, PostEditSubmitResponseKind.ambiguous);
  });
}
