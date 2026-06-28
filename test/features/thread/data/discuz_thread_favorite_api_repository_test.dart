import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/profile/data/models/profile_models.dart';
import 'package:y300/features/profile/data/repositories/profile_repository.dart';
import 'package:y300/features/thread/data/repositories/discuz_thread_favorite_api_repository.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('DiscuzThreadFavoriteApiRepository', () {
    test('posts favthread form data and returns success message', () async {
      final adapter = _ThreadFavoriteTestAdapter(
        responseJson: <String, dynamic>{
          'Version': '4',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{},
          'Message': <String, dynamic>{
            'messageval': 'favorite_do_success',
            'messagestr': '收藏成功',
          },
        },
      );
      final repository = _buildRepository(adapter: adapter);

      final result = await repository.favoriteThread(
        request: const ThreadFavoriteRequest(tid: '570617'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.message, '收藏成功');
      expect(adapter.lastUri?.queryParameters['module'], 'favthread');
      expect(adapter.lastUri?.queryParameters['version'], '4');
      expect(adapter.lastBody, contains('formhash=fe182126'));
      expect(adapter.lastBody, contains('id=570617'));
      expect(adapter.lastBody, contains('favoritesubmit=1'));
      expect(adapter.lastHeaders['referer'], contains('tid=570617'));
    });

    test('treats already-favorited response as success', () async {
      final adapter = _ThreadFavoriteTestAdapter(
        responseJson: <String, dynamic>{
          'Message': <String, dynamic>{
            'messageval': 'favorite_repeat',
            'messagestr': '已经收藏过该主题',
          },
        },
      );
      final repository = _buildRepository(adapter: adapter);

      final result = await repository.favoriteThread(
        request: const ThreadFavoriteRequest(tid: '570617'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.alreadyFavorited, isTrue);
    });

    test('returns failure when tid is empty', () async {
      final adapter = _ThreadFavoriteTestAdapter(responseJson: <String, dynamic>{});
      final repository = _buildRepository(adapter: adapter);

      final result = await repository.favoriteThread(
        request: const ThreadFavoriteRequest(tid: '  '),
      );

      expect(result.isFailure, isTrue);
      expect(adapter.called, isFalse);
    });
  });
}

DiscuzThreadFavoriteApiRepository _buildRepository({
  required _ThreadFavoriteTestAdapter adapter,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DiscuzThreadFavoriteApiRepository(
    profileRepository: _FakeProfileRepository.success(formhash: 'fe182126'),
    gateway: YamiboHttpGateway(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
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

class _ThreadFavoriteTestAdapter implements HttpClientAdapter {
  _ThreadFavoriteTestAdapter({
    required this.responseJson,
  });

  final Map<String, dynamic> responseJson;
  bool called = false;
  Uri? lastUri;
  String lastBody = '';
  Map<String, dynamic> lastHeaders = const <String, dynamic>{};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    called = true;
    lastUri = options.uri;
    lastHeaders = options.headers;
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
