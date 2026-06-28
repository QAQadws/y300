import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/profile/data/repositories/user_profile_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('UserProfileHtmlRepository requests mobile profile HTML', () async {
    final adapter = _UserProfileHtmlTestAdapter();
    final repository = _buildRepository(adapter);

    final result = await repository.getUserProfile(uid: '509957');

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull?.username, 'alice');
    final requested = adapter.requestedUris.single;
    expect(requested.path, '/home.php');
    expect(requested.queryParameters['mod'], 'space');
    expect(requested.queryParameters['uid'], '509957');
    expect(requested.queryParameters['do'], 'profile');
    expect(requested.queryParameters['mobile'], '2');
    expect(adapter.userAgents.single, contains('Mobile'));
  });

  test('UserProfileHtmlRepository requests my profile mobile HTML', () async {
    final adapter = _UserProfileHtmlTestAdapter();
    final repository = _buildRepository(adapter);

    final result = await repository.getMyProfile(uid: '597454');

    expect(result.isSuccess, isTrue);
    final requested = adapter.requestedUris.single;
    expect(requested.path, '/home.php');
    expect(requested.queryParameters['mod'], 'space');
    expect(requested.queryParameters['uid'], '597454');
    expect(requested.queryParameters['do'], 'profile');
    expect(requested.queryParameters['mycenter'], '1');
    expect(requested.queryParameters['mobile'], '2');
  });
}

UserProfileHtmlRepository _buildRepository(
  _UserProfileHtmlTestAdapter adapter,
) {
  final gateway = YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: Dio(
      BaseOptions(
        baseUrl: 'https://bbs.yamibo.com',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    )..httpClientAdapter = adapter,
    enableLog: false,
  );
  return UserProfileHtmlRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
  );
}

class _UserProfileHtmlTestAdapter implements HttpClientAdapter {
  final requestedUris = <Uri>[];
  final userAgents = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    userAgents.add(options.headers['User-Agent']?.toString() ?? '');
    return ResponseBody.fromString(_html, 200);
  }
}

const _html = '''
<html>
<body>
  <div class="header"><h2>alice的资料</h2></div>
  <div class="userinfo">
    <div class="avatar_m"><img src="https://bbs.yamibo.com/avatar.jpg"></div>
    <h2 class="name">alice</h2>
    <div class="user_box"><ul><li><span>12</span>总积分</li></ul></div>
    <div class="myinfo_list"><ul><li><b>个人资料</b></li><li>UID<span>509957</span></li></ul></div>
  </div>
</body>
</html>
''';
