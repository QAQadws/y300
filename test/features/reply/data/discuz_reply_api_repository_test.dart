import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
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
      final repository = _buildRepository(
        adapter: _ReplyTestAdapter(responseJson: <String, dynamic>{}),
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
