import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/profile/data/models/profile_models.dart';
import 'package:y300/features/profile/data/repositories/profile_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('DefaultForumFavoriteRepository', () {
    test(
      'favoriteForum posts favforum form data and returns success message',
      () async {
        final adapter = _ForumFavoriteTestAdapter(
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

        final result = await repository.favoriteForum(fid: '55');

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull?.message, '收藏成功');
        expect(adapter.lastUri?.queryParameters['module'], 'favforum');
        expect(adapter.lastUri?.queryParameters['version'], '4');
        expect(adapter.lastBody, contains('formhash=fe182126'));
        expect(adapter.lastBody, contains('id=55'));
        expect(adapter.lastBody, contains('favoritesubmit=1'));
      },
    );

    test(
      'unfavoriteForum posts favthread delete form data and returns success message',
      () async {
        final adapter = _ForumFavoriteTestAdapter(
          responseJson: <String, dynamic>{
            'Version': '4',
            'Charset': 'UTF-8',
            'Variables': <String, dynamic>{},
            'Message': <String, dynamic>{
              'messageval': 'do_success',
              'messagestr': '取消收藏成功',
            },
          },
        );
        final repository = _buildRepository(adapter: adapter);

        final result = await repository.unfavoriteForum(favid: '12345');

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull?.message, '取消收藏成功');
        expect(adapter.lastUri?.queryParameters['module'], 'favthread');
        expect(adapter.lastUri?.queryParameters['version'], '4');
        expect(adapter.lastUri?.queryParameters['op'], 'delete');
        expect(adapter.lastUri?.queryParameters['favid'], '12345');
        expect(adapter.lastBody, contains('formhash=fe182126'));
        expect(adapter.lastBody, contains('deletesubmit=true'));
      },
    );

    test('favoriteForum returns failure when formhash is empty', () async {
      final adapter = _ForumFavoriteTestAdapter(
        responseJson: <String, dynamic>{},
      );
      final repository = _buildRepository(
        adapter: adapter,
        profileRepository: _FakeProfileRepository.success(formhash: '  '),
      );

      final result = await repository.favoriteForum(fid: '55');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('formhash'));
      expect(adapter.called, isFalse);
    });

    test(
      'favoriteForum treats already-favorited response as success',
      () async {
        final adapter = _ForumFavoriteTestAdapter(
          responseJson: <String, dynamic>{
            'Message': <String, dynamic>{
              'messageval': 'favorite_repeat',
              'messagestr': '已经收藏过该版块',
            },
          },
        );
        final repository = _buildRepository(adapter: adapter);

        final result = await repository.favoriteForum(fid: '55');

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull?.alreadyApplied, isTrue);
      },
    );

    test(
      'unfavoriteForum treats already-removed response as success',
      () async {
        final adapter = _ForumFavoriteTestAdapter(
          responseJson: <String, dynamic>{
            'Message': <String, dynamic>{
              'messageval': 'favorite_does_not_exist',
              'messagestr': '该收藏不存在',
            },
          },
        );
        final repository = _buildRepository(adapter: adapter);

        final result = await repository.unfavoriteForum(favid: '12345');

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull?.alreadyApplied, isTrue);
      },
    );
  });
}

DefaultForumFavoriteRepository _buildRepository({
  required _ForumFavoriteTestAdapter adapter,
  ProfileRepository? profileRepository,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DefaultForumFavoriteRepository(
    apiClient: ApiClient(
      cookieStore: CookieStore(),
      logger: Logger(),
      dio: dio,
      enableLog: false,
    ),
    profileRepository:
        profileRepository ??
        _FakeProfileRepository.success(formhash: 'fe182126'),
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

class _ForumFavoriteTestAdapter implements HttpClientAdapter {
  _ForumFavoriteTestAdapter({required this.responseJson});

  final Map<String, dynamic> responseJson;
  bool called = false;
  Uri? lastUri;
  String lastBody = '';

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
