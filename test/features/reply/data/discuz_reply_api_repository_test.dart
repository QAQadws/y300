import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/reply/data/discuz_reply_remote_data_source.dart';
import 'package:y300/features/profile/data/models/profile_models.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/reply/data/discuz_reply_api_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('DiscuzReplyApiRepository', () {
    test('sends reply by api and returns success message', () async {
      final adapter = _ReplyTestAdapter(
        responseJson: <String, dynamic>{
          'Version': '4',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{},
          'Message': <String, dynamic>{
            'messageval': 'post_reply_succeed',
            'messagestr': '回复发布成功',
          },
        },
      );
      final repository = _buildRepository(adapter: adapter);

      final result = await repository.sendReply(
        draft: const ReplyDraft(
          fid: '33',
          tid: '570617',
          message: '测试回复',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.message, contains('成功'));
      expect(adapter.lastBody, contains('message=%E6%B5%8B%E8%AF%95%E5%9B%9E%E5%A4%8D'));
    });

    test('returns failure when message is empty', () async {
      final remoteDataSource = _FakeReplyRemoteDataSource(
        response: const ReplyRemoteResponse(data: <String, dynamic>{}, statusCode: 200),
      );
      final repository = _buildRepositoryWithRemote(
        remoteDataSource: remoteDataSource,
      );
      final result = await repository.sendReply(
        draft: const ReplyDraft(
          fid: '33',
          tid: '570617',
          message: '   ',
        ),
      );
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('不能为空'));
      expect(remoteDataSource.called, isFalse);
    });

    test('returns failure when formhash is empty', () async {
      final remoteDataSource = _FakeReplyRemoteDataSource(
        response: const ReplyRemoteResponse(data: <String, dynamic>{}, statusCode: 200),
      );
      final repository = _buildRepositoryWithRemote(
        profileRepository: _FakeProfileRepository.success(formhash: ''),
        remoteDataSource: remoteDataSource,
      );

      final result = await repository.sendReply(
        draft: const ReplyDraft(
          fid: '33',
          tid: '570617',
          message: '测试回复',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('formhash 为空'));
      expect(remoteDataSource.called, isFalse);
    });

    test('returns business failure when api message is not success', () async {
      final remoteDataSource = _FakeReplyRemoteDataSource(
        response: const ReplyRemoteResponse(
          data: <String, dynamic>{
            'Message': <String, dynamic>{
              'messageval': 'post_reply_need_moderation',
              'messagestr': '回复需要审核',
            },
          },
          statusCode: 200,
        ),
      );
      final repository = _buildRepositoryWithRemote(
        remoteDataSource: remoteDataSource,
      );

      final result = await repository.sendReply(
        draft: const ReplyDraft(
          fid: '33',
          tid: '570617',
          message: '测试回复',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.business);
      expect(result.errorOrNull?.message, contains('审核'));
      expect(result.errorOrNull?.statusCode, 200);
    });

    test('maps dio timeout exception to timeout failure', () async {
      final repository = _buildRepositoryWithRemote(
        remoteDataSource: _FakeReplyRemoteDataSource(
          exception: DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
            message: 'timeout',
          ),
        ),
      );

      final result = await repository.sendReply(
        draft: const ReplyDraft(
          fid: '33',
          tid: '570617',
          message: '测试回复',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.timeout);
    });

    test('maps unauthorized dio response to unauthorized failure', () async {
      final repository = _buildRepositoryWithRemote(
        remoteDataSource: _FakeReplyRemoteDataSource(
          exception: DioException(
            requestOptions: RequestOptions(path: '/'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 403,
              data: 'forbidden',
            ),
          ),
        ),
      );

      final result = await repository.sendReply(
        draft: const ReplyDraft(
          fid: '33',
          tid: '570617',
          message: '测试回复',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.unauthorized);
      expect(result.errorOrNull?.statusCode, 403);
      expect(result.errorOrNull?.raw, 'forbidden');
    });

    test('maps server dio response to server failure', () async {
      final repository = _buildRepositoryWithRemote(
        remoteDataSource: _FakeReplyRemoteDataSource(
          exception: DioException(
            requestOptions: RequestOptions(path: '/'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 500,
              data: 'server error',
            ),
          ),
        ),
      );

      final result = await repository.sendReply(
        draft: const ReplyDraft(
          fid: '33',
          tid: '570617',
          message: '测试回复',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.server);
      expect(result.errorOrNull?.statusCode, 500);
    });
  });
}

DiscuzReplyApiRepository _buildRepository({
  required _ReplyTestAdapter adapter,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DiscuzReplyApiRepository(
    profileRepository: _FakeProfileRepository.success(formhash: 'fe182126'),
    cookieStore: CookieStore(),
    dio: dio,
  );
}

DiscuzReplyApiRepository _buildRepositoryWithRemote({
  required DiscuzReplyRemoteDataSource remoteDataSource,
  ProfileRepository? profileRepository,
}) {
  return DiscuzReplyApiRepository(
    profileRepository:
        profileRepository ?? _FakeProfileRepository.success(formhash: 'fe182126'),
    cookieStore: CookieStore(),
    remoteDataSource: remoteDataSource,
  );
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository.success({required String formhash})
    : _result = ApiSuccess<ProfileData>(
        ProfileData(
          uid: '1',
          username: 'tester',
          avatar: '',
          groupId: '10',
          credits: 0,
          posts: 0,
          threads: 0,
          formhash: formhash,
        ),
      );

  final ApiResult<ProfileData> _result;

  @override
  Future<ApiResult<ProfileData>> getProfile() async => _result;
}

class _FakeReplyRemoteDataSource implements DiscuzReplyRemoteDataSource {
  _FakeReplyRemoteDataSource({
    this.response,
    this.exception,
  });

  final ReplyRemoteResponse? response;
  final Object? exception;
  bool called = false;

  @override
  Future<ReplyRemoteResponse> sendReply(ReplySubmitPayload payload) async {
    called = true;
    final exception = this.exception;
    if (exception != null) {
      throw exception;
    }
    return response ??
        const ReplyRemoteResponse(data: <String, dynamic>{}, statusCode: 200);
  }
}

class _ReplyTestAdapter implements HttpClientAdapter {
  _ReplyTestAdapter({
    required this.responseJson,
  });

  final Map<String, dynamic> responseJson;
  String lastBody = '';

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = <int>[];
      for (final chunk in chunks) {
        bytes.addAll(chunk);
      }
      lastBody = utf8.decode(bytes, allowMalformed: true);
    }

    return ResponseBody.fromString(
      jsonEncode(responseJson),
      200,
      headers: const <String, List<String>>{},
    );
  }
}
