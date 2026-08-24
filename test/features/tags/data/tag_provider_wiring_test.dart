import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart'
    as forum_adapters;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('production Tag directory provider remains desktop HTML-first', () {
    final gateway = YamiboHttpGateway(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: Dio(BaseOptions(baseUrl: 'https://bbs.yamibo.com')),
      enableLog: false,
    );
    final container = ProviderContainer(
      overrides: [
        yamiboHtmlClientProvider.overrideWithValue(
          YamiboHtmlClient(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(forumTagDirectoryRepositoryProvider),
      isA<forum_adapters.DiscuzForumTagDirectoryRepository>(),
    );
  });
}
