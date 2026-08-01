import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/services/discuz_post_edit_delete_response_parser.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_attachment_delete_uri_builder.dart';

void main() {
  test('parses Discuz deleteattach CDATA counts fail closed', () {
    const parser = DiscuzPostEditDeleteResponseParser();

    expect(
      parser.parse(body: '<root><![CDATA[1]]></root>', aid: '12').outcome,
      PostEditAttachmentDeleteOutcome.deleted,
    );
    expect(
      parser.parse(body: '<root><![CDATA[0]]></root>', aid: '12').outcome,
      PostEditAttachmentDeleteOutcome.notDeleted,
    );
    expect(
      parser.parse(body: '<root><![CDATA[nope]]></root>', aid: '12').outcome,
      PostEditAttachmentDeleteOutcome.unconfirmed,
    );
    expect(
      parser.parse(body: '<root></root>', aid: '12').outcome,
      PostEditAttachmentDeleteOutcome.unconfirmed,
    );
  });

  test('builds a same-host deleteattach URI with the current credentials', () {
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
    final uri = const PostEditAttachmentDeleteUriBuilder().build(
      PostEditAttachmentDeleteCommand(
        target: target,
        aid: '12',
        formHash: 'hash',
        expectedBaselineFingerprint: 'baseline',
      ),
    );

    expect(uri.host, 'bbs.yamibo.com');
    expect(uri.path, '/forum.php');
    expect(uri.queryParameters['mod'], 'ajax');
    expect(uri.queryParameters['action'], 'deleteattach');
    expect(uri.queryParameters['aids[]'], '12');
    expect(uri.queryParameters['tid'], '20');
    expect(uri.queryParameters['pid'], '30');
    expect(uri.queryParameters['formhash'], 'hash');
  });
}
