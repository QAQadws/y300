import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_api_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/composer_shared/data/composer_attachment_remote_data_source.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscuzComposerAttachmentDioDataSource', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('checks upload permission from checkpost variables', () async {
      final adapter = _UploadRemoteTestAdapter(
        responseBody: jsonEncode(_checkPostResponse()),
      );
      final dataSource = _buildDataSource(adapter);

      final permission = await dataSource.checkUploadPermission(fid: '33');

      expect(adapter.lastUri.queryParameters['module'], 'checkpost');
      expect(adapter.lastUri.queryParameters['version'], '1');
      expect(adapter.lastUri.queryParameters['fid'], '33');
      expect(permission.uid, '597454');
      expect(permission.username, '2834758851');
      expect(permission.formHash, 'cba80c43');
      expect(permission.uploadHash, 'd3bd2566e6639c93880a3703505a1286');
      expect(permission.allowedExtensions, {'jpg', 'jpeg', 'gif', 'png'});
      expect(permission.attachRemain.size, -1);
      expect(permission.attachRemain.count, -1);
      expect(permission.allowedExtensions, isNot(contains('mp3')));
    });

    test('uploads image through forumupload multipart endpoint', () async {
      final tempDir = io.Directory.systemTemp.createTempSync(
        'y300-composer-upload-test-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final imageFile = io.File('${tempDir.path}/photo.jpg')
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final adapter = _UploadRemoteTestAdapter(responseBody: '123456');
      final dataSource = _buildDataSource(adapter);

      final response = await dataSource.uploadImage(
        fid: '33',
        permission: _permission(),
        file: ComposerLocalImageFile(
          path: imageFile.path,
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
        ),
      );

      expect(response.aid, '123456');
      expect(response.rawBody, '123456');
      expect(response.statusCode, 200);
      expect(adapter.lastUri.queryParameters['module'], 'forumupload');
      expect(adapter.lastUri.queryParameters['version'], '4');
      expect(adapter.lastUri.queryParameters['fid'], '33');
      expect(adapter.lastUri.queryParameters['type'], 'image');
      expect(adapter.lastUri.queryParameters['filetype'], 'image/jpeg');
      expect(adapter.lastBody, contains('name="uid"'));
      expect(adapter.lastBody, contains('597454'));
      expect(adapter.lastBody, contains('name="hash"'));
      expect(adapter.lastBody, contains('upload-hash'));
      expect(adapter.lastBody, contains('name="Filedata"'));
      expect(adapter.lastBody, contains('filename="photo.jpg"'));
    });

    test('adds cookies from store and saves response cookies', () async {
      final adapter = _UploadRemoteTestAdapter(
        responseBody: jsonEncode(_checkPostResponse()),
        responseHeaders: const <String, List<String>>{
          'set-cookie': <String>['upload_next=456; Path=/'],
        },
      );
      final cookieStore = CookieStore();
      final uri = Uri.parse('https://bbs.yamibo.com/api/mobile/index.php');
      await cookieStore.saveFromSetCookie(uri, const <String>[
        'upload_cookie=123; Path=/',
      ]);
      final dataSource = _buildDataSource(adapter, cookieStore: cookieStore);

      await dataSource.checkUploadPermission(fid: '33');

      expect(adapter.lastHeaders['Cookie'], contains('upload_cookie=123'));
      final cookieHeader = await cookieStore.readCookieHeader(uri);
      expect(cookieHeader, contains('upload_next=456'));
    });
  });
}

DiscuzComposerAttachmentDioDataSource _buildDataSource(
  _UploadRemoteTestAdapter adapter, {
  CookieStore? cookieStore,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  final store = cookieStore ?? CookieStore();
  final gateway = YamiboHttpGateway(
    cookieStore: store,
    logger: Logger(level: Level.off),
    dio: dio,
    enableLog: false,
  );
  return DiscuzComposerAttachmentDioDataSource(
    cookieStore: store,
    apiClient: YamiboApiClient(gateway: gateway),
    gateway: gateway,
  );
}

ComposerImageUploadPermission _permission() {
  return const ComposerImageUploadPermission(
    uid: '597454',
    uploadHash: 'upload-hash',
    allowedExtensions: {'jpg', 'jpeg', 'png', 'gif'},
    attachRemain: ComposerAttachRemain(size: -1, count: -1),
  );
}

Map<String, dynamic> _checkPostResponse() {
  return <String, dynamic>{
    'Version': '1',
    'Charset': 'UTF-8',
    'Variables': <String, dynamic>{
      'member_uid': '597454',
      'member_username': '2834758851',
      'formhash': 'cba80c43',
      'allowperm': <String, dynamic>{
        'allowupload': <String, String>{
          'jpg': '-1',
          'jpeg': '1',
          'gif': '-1',
          'png': '-1',
          'mp3': '0',
        },
        'attachremain': <String, String>{'size': '-1', 'count': '-1'},
        'uploadhash': 'd3bd2566e6639c93880a3703505a1286',
      },
    },
  };
}

class _UploadRemoteTestAdapter implements HttpClientAdapter {
  _UploadRemoteTestAdapter({
    required this.responseBody,
    this.responseHeaders = const <String, List<String>>{},
  });

  final String responseBody;
  final Map<String, List<String>> responseHeaders;
  Uri lastUri = Uri();
  Map<String, dynamic> lastHeaders = <String, dynamic>{};
  String lastBody = '';

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = <int>[];
      for (final chunk in chunks) {
        bytes.addAll(chunk);
      }
      lastBody = utf8.decode(bytes, allowMalformed: true);
    }

    return ResponseBody.fromString(responseBody, 200, headers: responseHeaders);
  }
}
