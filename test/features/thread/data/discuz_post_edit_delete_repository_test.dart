import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/repositories/discuz_post_edit_repository.dart';
import 'package:y300/features/thread/data/services/post_edit_remote_data_source.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

void main() {
  test(
    'repository uses the target delete URI and parses the response',
    () async {
      final source = _FakeDeleteDataSource('<root><![CDATA[1]]></root>');
      final repository = DiscuzPostEditRepository(remoteDataSource: source);
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

      final result = await repository.deleteImage(
        PostEditAttachmentDeleteCommand(
          target: target,
          aid: '12',
          formHash: 'current-hash',
          expectedBaselineFingerprint: 'baseline',
        ),
      );

      expect(
        result.dataOrNull!.outcome,
        PostEditAttachmentDeleteOutcome.deleted,
      );
      expect(source.lastDeleteUri?.queryParameters['aids[]'], '12');
      expect(source.lastDeleteUri?.queryParameters['tid'], '20');
      expect(source.lastDeleteUri?.queryParameters['pid'], '30');
      expect(source.lastDeleteUri?.queryParameters['formhash'], 'current-hash');
    },
  );
}

final class _FakeDeleteDataSource implements PostEditRemoteDataSource {
  _FakeDeleteDataSource(this.body);

  final String body;
  Uri? lastDeleteUri;

  @override
  Future<ApiResult<PostEditRemoteDocument>> get(Uri editUri) async {
    return ApiSuccess(PostEditRemoteDocument(sourceUri: editUri, html: ''));
  }

  @override
  Future<ApiResult<PostEditRemoteDeleteDocument>> deleteImage(
    Uri deleteUri,
  ) async {
    lastDeleteUri = deleteUri;
    return ApiSuccess(
      PostEditRemoteDeleteDocument(sourceUri: deleteUri, body: body),
    );
  }
}
