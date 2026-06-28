import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_resource_client.dart';
import 'package:y300/features/forum/data/services/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/repositories/forum_home_chrome_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loadChrome requests mobile index once with mobile user agent', () async {
    final adapter = _ForumHomeChromeTestAdapter();
    final repository = _buildRepository(adapter);

    final result = await repository.loadChrome();

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.carouselItems, hasLength(1));
    expect(
      result.dataOrNull!.carouselItems.single.targetUrl,
      'https://bbs.yamibo.com/thread-570956-1-1.html',
    );
    expect(result.dataOrNull!.carouselItems.single.aspectRatio, closeTo(3.0, 0.01));
    expect(
      adapter.htmlRequestedUris,
      <String>['https://bbs.yamibo.com/index.php?mobile=2'],
    );
    expect(adapter.userAgents.single, contains('Mobile'));
    expect(
      adapter.imageRequestedUris,
      <String>['https://bbs.yamibo.com/data/attachment/block/95/banner.jpg'],
    );
  });

  test('loadChrome returns empty carousel without fallback when mobile index is empty', () async {
    final adapter = _ForumHomeChromeTestAdapter(
      emptyMobileIndex: true,
    );
    final repository = _buildRepository(adapter);

    final result = await repository.loadChrome();

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.carouselItems, isEmpty);
    expect(
      adapter.htmlRequestedUris,
      <String>['https://bbs.yamibo.com/index.php?mobile=2'],
    );
    expect(adapter.imageRequestedUris, isEmpty);
  });
}

DiscuzForumHomeChromeRepository _buildRepository(
  _ForumHomeChromeTestAdapter adapter,
) {
  final gateway = YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: Dio(
      BaseOptions(
        baseUrl: 'https://bbs.yamibo.com',
        validateStatus: (status) => status != null && status >= 200 && status < 400,
      ),
    )..httpClientAdapter = adapter,
    enableLog: false,
  );
  return DiscuzForumHomeChromeRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
    imageProbe: ForumHomeCarouselImageProbe(
      resourceClient: YamiboResourceClient(gateway: gateway),
      headerBuilder: const _StaticImageRequestHeaderBuilder(),
    ),
  );
}

class _ForumHomeChromeTestAdapter implements HttpClientAdapter {
  _ForumHomeChromeTestAdapter({
    this.emptyMobileIndex = false,
  });

  final bool emptyMobileIndex;
  final htmlRequestedUris = <String>[];
  final imageRequestedUris = <String>[];
  final userAgents = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isImageRequest = options.uri.path.endsWith('/banner.jpg');
    if (isImageRequest) {
      imageRequestedUris.add(options.uri.toString());
    } else {
      htmlRequestedUris.add(options.uri.toString());
      userAgents.add(options.headers['User-Agent']?.toString() ?? '');
    }
    if (isImageRequest) {
      return ResponseBody.fromBytes(_pngBytes(width: 300, height: 100), 200);
    }
    if (options.uri.path.endsWith('/index.php') && emptyMobileIndex) {
      return ResponseBody.fromString('<html><body id="forum"></body></html>', 200);
    }
    if (options.uri.path.endsWith('/index.php')) {
      return ResponseBody.fromString(
        '''
<body id="forum">
  <div class="index-top-wrapper">
    <div class="yami-swiper">
      <div class="swiper-slide">
        <a href="thread-570956-1-1.html">
          <img src="data/attachment/block/95/banner.jpg">
        </a>
      </div>
    </div>
  </div>
</body>
''',
        200,
      );
    }

    return ResponseBody.fromString(
      jsonEncode(<String, String>{'unexpected': options.uri.toString()}),
      404,
    );
  }

  Uint8List _pngBytes({required int width, required int height}) {
    final bytes = Uint8List(24);
    bytes.setAll(0, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final data = ByteData.sublistView(bytes);
    data.setUint32(16, width, Endian.big);
    data.setUint32(20, height, Endian.big);
    return bytes;
  }
}

class _StaticImageRequestHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageRequestHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{
      'User-Agent': DiscuzImageRequestHeaderBuilder.browserUserAgent,
      'Accept': DiscuzImageRequestHeaderBuilder.imageAcceptHeader,
      'Referer': 'https://bbs.yamibo.com/',
    };
  }
}
