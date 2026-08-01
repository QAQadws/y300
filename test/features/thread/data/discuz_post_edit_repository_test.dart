import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/repositories/discuz_post_edit_repository.dart';
import 'package:y300/features/thread/data/services/post_edit_remote_data_source.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

const _fixturePath =
    'test/fixtures/thread/post_edit/mobile_post_edit_form.html';

void main() {
  final target = PostEditTarget(
    editUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=557857&pid=41587383&page=215',
    ),
    fid: '5',
    tid: '557857',
    pid: '41587383',
    page: 215,
    isFirstPost: false,
  );

  test(
    'GETs the original edit URI and prepares the fixture decision',
    () async {
      final source = _FakeRemoteDataSource(
        ApiSuccess(
          PostEditRemoteDocument(
            sourceUri: target.editUri,
            html: _readFixture(),
          ),
        ),
      );
      final result = await DiscuzPostEditRepository(
        remoteDataSource: source,
      ).loadForm(target);

      expect(source.lastUri, target.editUri);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.isNativeSupported, isTrue);
      expect(result.dataOrNull!.snapshot!.baselineFingerprint, hasLength(64));
    },
  );

  test('maps network errors without hiding them as a parse fallback', () async {
    final result = await DiscuzPostEditRepository(
      remoteDataSource: _FakeRemoteDataSource(
        const ApiFailure(
          ApiError(type: ApiErrorType.network, message: 'offline'),
        ),
      ),
    ).loadForm(target);

    expect(result, isA<ApiFailure<PostEditPreparation>>());
    expect(result.errorOrNull!.type, ApiErrorType.network);
  });

  test('maps parse errors to an explicit WebView-only preparation', () async {
    final result = await DiscuzPostEditRepository(
      remoteDataSource: _FakeRemoteDataSource(
        ApiSuccess(
          PostEditRemoteDocument(
            sourceUri: target.editUri,
            html: '<html><body>请先登录</body></html>',
          ),
        ),
      ),
    ).loadForm(target);

    expect(result.isSuccess, isTrue);
    final preparation = result.dataOrNull!;
    expect(preparation.isWebViewOnly, isTrue);
    expect(
      (preparation.decision as PostEditWebViewOnly).reason,
      PostEditFallbackReason.authenticationRequired,
    );
  });

  test('keeps a structurally parsed but unsupported form on WebView', () async {
    final html = _readFixture().replaceFirst(
      '</form>',
      '<input type="hidden" name="plugin_custom" value="1"></form>',
    );
    final result = await DiscuzPostEditRepository(
      remoteDataSource: _FakeRemoteDataSource(
        ApiSuccess(
          PostEditRemoteDocument(sourceUri: target.editUri, html: html),
        ),
      ),
    ).loadForm(target);

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.isWebViewOnly, isTrue);
    expect(
      (result.dataOrNull!.decision as PostEditWebViewOnly).reason,
      PostEditFallbackReason.unsupportedPluginField,
    );
  });
}

class _FakeRemoteDataSource implements PostEditRemoteDataSource {
  _FakeRemoteDataSource(this.result);

  final ApiResult<PostEditRemoteDocument> result;
  Uri? lastUri;

  @override
  Future<ApiResult<PostEditRemoteDocument>> get(Uri editUri) async {
    lastUri = editUri;
    return result;
  }
}

String _readFixture() {
  return File(_fixturePath).readAsStringSync(encoding: utf8);
}
