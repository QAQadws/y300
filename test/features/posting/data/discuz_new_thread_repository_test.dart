import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/posting/data/new_thread_remote_data_source.dart';
import 'package:y300/features/posting/data/new_thread_repository.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

void main() {
  group('DiscuzNewThreadRepository', () {
    test('returns success with tid/pid when remote responds positively',
        () async {
      final remote = _FakeRemote(
        response: const NewThreadRemoteResponse(
          data: <String, dynamic>{
            'Variables': <String, dynamic>{
              'tid': '999001',
              'pid': '888001',
            },
            'Message': <String, dynamic>{
              'messageval': 'post_newthread_succeed',
              'messagestr': '主题已发布',
            },
          },
          statusCode: 200,
        ),
      );
      final repository = _build(remote: remote);

      final result = await repository.submit(payload: _payload());

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.tid, '999001');
      expect(result.dataOrNull?.pid, '888001');
      expect(remote.submittedForms, hasLength(1));
    });

    test('translates post_type_isnull to business failure with code', () async {
      final repository = _build(
        remote: _FakeRemote(
          response: const NewThreadRemoteResponse(
            data: <String, dynamic>{
              'Message': <String, dynamic>{
                'messageval': 'post_type_isnull',
                'messagestr': '请选择主题分类',
              },
            },
            statusCode: 200,
          ),
        ),
      );

      final result = await repository.submit(payload: _payload());

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.business);
      expect(result.errorOrNull?.code, 'post_type_isnull');
      expect(result.errorOrNull?.message, '请选择主题分类');
    });

    test('translates post_flood_ctrl to business failure', () async {
      final repository = _build(
        remote: _FakeRemote(
          response: const NewThreadRemoteResponse(
            data: <String, dynamic>{
              'Message': <String, dynamic>{
                'messageval': 'post_flood_ctrl',
                'messagestr': '发帖间隔过短',
              },
            },
            statusCode: 200,
          ),
        ),
      );

      final result = await repository.submit(payload: _payload());

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, 'post_flood_ctrl');
    });

    test('translates postperm_login_nopermission to business failure',
        () async {
      final repository = _build(
        remote: _FakeRemote(
          response: const NewThreadRemoteResponse(
            data: <String, dynamic>{
              'Message': <String, dynamic>{
                'messageval': 'postperm_login_nopermission',
                'messagestr': '请登录后再发帖',
              },
            },
            statusCode: 200,
          ),
        ),
      );

      final result = await repository.submit(payload: _payload());

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, 'postperm_login_nopermission');
    });

    test('maps DioException timeout to ApiErrorType.timeout', () async {
      final repository = _build(
        remote: _FakeRemote(
          exception: DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionTimeout,
            message: 'timeout',
          ),
        ),
      );

      final result = await repository.submit(payload: _payload());

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.timeout);
    });

    test('maps DioException 401/403 to ApiErrorType.unauthorized', () async {
      final repository = _build(
        remote: _FakeRemote(
          exception: DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: ''),
              statusCode: 401,
            ),
            message: 'forbidden',
          ),
        ),
      );

      final result = await repository.submit(payload: _payload());

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.unauthorized);
    });

    test('passes payload form fields verbatim into NewThreadSubmitForm',
        () async {
      final remote = _FakeRemote(
        response: const NewThreadRemoteResponse(
          data: <String, dynamic>{
            'Variables': <String, dynamic>{
              'tid': '777001',
              'pid': '666001',
            },
            'Message': <String, dynamic>{
              'messageval': 'post_newthread_succeed',
              'messagestr': 'ok',
            },
          },
          statusCode: 200,
        ),
      );
      final repository = _build(remote: remote);

      await repository.submit(
        payload: _payload(
          subject: '标题',
          message: '正文',
          typeid: '101',
          useSignature: false,
          allowNoticeAuthor: true,
          bbCodeOff: true,
          smileyOff: true,
          parseUrlOff: true,
          uploadedAttachmentAids: const ['1234', '5678'],
        ),
      );

      final form = remote.submittedForms.single.toFormData();
      expect(form['formhash'], 'fh');
      expect(form['topicsubmit'], 'yes');
      expect(form['subject'], '标题');
      expect(form['message'], '正文');
      expect(form['typeid'], '101');
      expect(form['special'], '0');
      expect(form['usesig'], '0');
      expect(form['allownoticeauthor'], '1');
      expect(form['bbcodeoff'], '1');
      expect(form['smileyoff'], '1');
      expect(form['parseurloff'], '1');
      expect(form['allowphoto'], '1');
      expect(form['attachnew[1234][description]'], '');
      expect(form['attachnew[5678][description]'], '');
    });
  });
}

NewThreadDraftPayload _payload({
  String fid = '33',
  String formHash = 'fh',
  String subject = '标题',
  String message = '正文',
  String typeid = '0',
  bool useSignature = true,
  bool allowNoticeAuthor = false,
  bool bbCodeOff = false,
  bool smileyOff = false,
  bool parseUrlOff = false,
  List<String> uploadedAttachmentAids = const <String>[],
}) {
  return NewThreadDraftPayload(
    fid: fid,
    formHash: formHash,
    subject: subject,
    message: message,
    typeid: typeid,
    useSignature: useSignature,
    allowNoticeAuthor: allowNoticeAuthor,
    bbCodeOff: bbCodeOff,
    smileyOff: smileyOff,
    parseUrlOff: parseUrlOff,
    uploadedAttachmentAids: uploadedAttachmentAids,
  );
}

DiscuzNewThreadRepository _build({required NewThreadRemoteDataSource remote}) {
  return DiscuzNewThreadRepository(
    remoteDataSource: remote,
  );
}

class _FakeRemote implements NewThreadRemoteDataSource {
  _FakeRemote({this.response, this.exception});

  final NewThreadRemoteResponse? response;
  final Object? exception;
  final List<NewThreadSubmitForm> submittedForms = <NewThreadSubmitForm>[];

  @override
  Future<NewThreadRemoteResponse> submit(NewThreadSubmitForm form) async {
    submittedForms.add(form);
    final exception = this.exception;
    if (exception != null) {
      throw exception;
    }
    return response ??
        const NewThreadRemoteResponse(
          data: <String, dynamic>{},
          statusCode: 200,
        );
  }
}
