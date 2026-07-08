import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';

void main() {
  group('YamiboCatalogHtmlFetcher', () {
    test(
      'uses desktop tag page html request with normalized catalog url',
      () async {
        final htmlClient = _RecordingYamiboHtmlClient(
          result: const ApiSuccess<String>('<html>catalog</html>'),
        );
        final fetcher = YamiboCatalogHtmlFetcher(htmlClient: htmlClient);

        final html = await fetcher.fetchHtml(
          'https://bbs.yamibo.com/misc.php?mod=tag&id=18235',
        );

        expect(html, '<html>catalog</html>');
        expect(htmlClient.desktopCalls, hasLength(1));
        expect(htmlClient.mobileCalls, isEmpty);

        final call = htmlClient.desktopCalls.single;
        expect(call.path, '/misc.php');
        expect(call.queryParameters, containsPair('mod', 'tag'));
        expect(call.queryParameters, containsPair('id', '18235'));
        expect(call.queryParameters, containsPair('type', 'thread'));
        expect(call.queryParameters, containsPair('page', '1'));
        expect(call.context.kind, YamiboRequestKind.html);
        expect(call.context.operation, 'comic.catalog.fetch');
        expect(call.context.pageKind, 'comic.catalog');
      },
    );

    test('returns null when desktop html request fails', () async {
      final fetcher = YamiboCatalogHtmlFetcher(
        htmlClient: _RecordingYamiboHtmlClient(
          result: const ApiFailure<String>(
            ApiError(type: ApiErrorType.network, message: 'offline'),
          ),
        ),
      );

      final html = await fetcher.fetchHtml(
        'https://bbs.yamibo.com/misc.php?mod=tag&id=18235',
      );

      expect(html, isNull);
    });
  });
}

class _RecordingYamiboHtmlClient implements YamiboHtmlClient {
  _RecordingYamiboHtmlClient({required this.result});

  final ApiResult<String> result;
  final List<_HtmlPageCall> desktopCalls = <_HtmlPageCall>[];
  final List<_HtmlPageCall> mobileCalls = <_HtmlPageCall>[];

  @override
  Future<ApiResult<String>> getDesktopPage({
    required String path,
    Map<String, String> queryParameters = const <String, String>{},
    required YamiboRequestContext context,
    Uri? referer,
    CancelToken? cancelToken,
  }) async {
    desktopCalls.add(
      _HtmlPageCall(
        path: path,
        queryParameters: Map<String, String>.from(queryParameters),
        context: context,
      ),
    );
    return result;
  }

  @override
  Future<ApiResult<String>> getMobilePage({
    required String path,
    Map<String, String> queryParameters = const <String, String>{},
    required YamiboRequestContext context,
    Uri? referer,
    CancelToken? cancelToken,
  }) async {
    mobileCalls.add(
      _HtmlPageCall(
        path: path,
        queryParameters: Map<String, String>.from(queryParameters),
        context: context,
      ),
    );
    return result;
  }
}

class _HtmlPageCall {
  const _HtmlPageCall({
    required this.path,
    required this.queryParameters,
    required this.context,
  });

  final String path;
  final Map<String, String> queryParameters;
  final YamiboRequestContext context;
}
