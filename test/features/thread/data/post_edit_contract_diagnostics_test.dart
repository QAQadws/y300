import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/repositories/discuz_post_edit_repository.dart';
import 'package:y300/features/thread/data/services/post_edit_remote_data_source.dart';
import 'package:y300/features/thread/domain/models/post_edit_diagnostic_models.dart';
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

  test('records fallback reason without field values or URI', () async {
    final recorder = _RecordingDiagnosticRecorder();
    final html = File(_fixturePath)
        .readAsStringSync(encoding: utf8)
        .replaceFirst(
          '</form>',
          '<input type="hidden" name="plugin_custom" value="secret-value"></form>',
        );
    final repository = DiscuzPostEditRepository(
      remoteDataSource: _FakeRemoteDataSource(
        ApiSuccess(
          PostEditRemoteDocument(sourceUri: target.editUri, html: html),
        ),
      ),
      diagnosticRecorder: recorder,
    );

    final result = await repository.loadForm(target);

    expect(result.isSuccess, isTrue);
    expect(
      recorder.events.single.reasonCode,
      PostEditContractReasonCode.unsupportedPluginField,
    );
    final fields = recorder.events.single.toSafeLogFields();
    expect(fields['target'], '5/557857/41587383');
    expect(fields['controlCount'], isA<int>());
    expect(fields['controlNameDigest'], hasLength(64));
    expect(fields.toString(), isNot(contains('secret-value')));
    expect(fields.toString(), isNot(contains('formhash')));
    expect(fields.toString(), isNot(contains('https://')));
  });

  test('records authentication and network reasons', () async {
    final authRecorder = _RecordingDiagnosticRecorder();
    final authRepository = DiscuzPostEditRepository(
      remoteDataSource: _FakeRemoteDataSource(
        ApiSuccess(
          PostEditRemoteDocument(
            sourceUri: target.editUri,
            html: '<html><body>请先登录</body></html>',
          ),
        ),
      ),
      diagnosticRecorder: authRecorder,
    );
    await authRepository.loadForm(target);
    expect(
      authRecorder.events.single.reasonCode,
      PostEditContractReasonCode.authenticationRequired,
    );

    final networkRecorder = _RecordingDiagnosticRecorder();
    final networkRepository = DiscuzPostEditRepository(
      remoteDataSource: _FakeRemoteDataSource(
        const ApiFailure(
          ApiError(type: ApiErrorType.timeout, message: 'network detail'),
        ),
      ),
      diagnosticRecorder: networkRecorder,
    );
    await networkRepository.loadForm(target);
    expect(
      networkRecorder.events.single.reasonCode,
      PostEditContractReasonCode.networkFailure,
    );
  });
}

final class _RecordingDiagnosticRecorder
    implements PostEditContractDiagnosticRecorder {
  final events = <PostEditContractDiagnosticEvent>[];

  @override
  void record(PostEditContractDiagnosticEvent event) {
    events.add(event);
  }
}

final class _FakeRemoteDataSource implements PostEditRemoteDataSource {
  _FakeRemoteDataSource(this.getResult);

  final ApiResult<PostEditRemoteDocument> getResult;

  @override
  Future<ApiResult<PostEditRemoteDocument>> get(Uri editUri) async {
    return getResult;
  }

  @override
  Future<ApiResult<PostEditRemoteDeleteDocument>> deleteImage(
    Uri deleteUri,
  ) async {
    return ApiSuccess(
      PostEditRemoteDeleteDocument(sourceUri: deleteUri, body: '<![CDATA[0]]>'),
    );
  }

  @override
  Future<ApiResult<PostEditRemoteSubmitDocument>> submit({
    required Uri submitUri,
    required List<MapEntry<String, String>> fields,
  }) async {
    return ApiSuccess(
      PostEditRemoteSubmitDocument(
        sourceUri: submitUri,
        statusCode: 200,
        body: '',
      ),
    );
  }
}
