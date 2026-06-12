import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/posting/data/posting_form_metadata_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscuzPostingFormMetadataRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('parses formhash + threadtypes (Map shape) + forum name', () async {
      final adapter = _Adapter(
        responseJson: <String, dynamic>{
          'Version': '4',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{
            'formhash': 'fh-meta',
            'forum': <String, dynamic>{'name': '随便聊聊'},
            'threadtypes': <String, dynamic>{
              'required': '1',
              'types': <String, dynamic>{
                '101': '杂谈',
                '102': '资源',
              },
            },
          },
        },
      );
      final repository = _build(adapter);

      final result = await repository.getFormMetadata(fid: '33');

      expect(result.isSuccess, isTrue);
      final metadata = result.dataOrNull!;
      expect(metadata.fid, '33');
      expect(metadata.formHash, 'fh-meta');
      expect(metadata.forumName, '随便聊聊');
      expect(metadata.typeRequired, isTrue);
      expect(metadata.threadTypes.map((t) => t.id), containsAll(['101', '102']));
      expect(adapter.lastUri.queryParameters['module'], 'forumdisplay');
      expect(adapter.lastUri.queryParameters['fid'], '33');
    });

    test('returns business failure when Message node is present', () async {
      final adapter = _Adapter(
        responseJson: <String, dynamic>{
          'Version': '4',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{},
          'Message': <String, dynamic>{
            'messageval': 'forum_isnull',
            'messagestr': '该版块不存在',
          },
        },
      );
      final repository = _build(adapter);

      final result = await repository.getFormMetadata(fid: '999999');
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.business);
    });
  });
}

DiscuzPostingFormMetadataRepository _build(_Adapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final apiClient = ApiClient(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: dio,
    enableLog: false,
  );
  return DiscuzPostingFormMetadataRepository(apiClient);
}

class _Adapter implements HttpClientAdapter {
  _Adapter({required this.responseJson});

  final Map<String, dynamic> responseJson;
  Uri lastUri = Uri();

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    return ResponseBody.fromString(
      jsonEncode(responseJson),
      200,
      headers: const <String, List<String>>{},
    );
  }
}
