import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/reply/data/reply_form_preparation_data_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscuzReplyFormPreparationDataSource', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('gets reply form html with cookies and stores response cookies', () async {
      final adapter = _ReplyFormTestAdapter(
        html: _formHtml(),
        headers: const <String, List<String>>{
          'set-cookie': <String>['next_cookie=456; Path=/'],
        },
      );
      final cookieStore = CookieStore();
      final uri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=572063&repquote=41554317&mobile=2',
      );
      await cookieStore.saveFromSetCookie(
        uri,
        const <String>['reply_cookie=123; Path=/'],
      );
      final dataSource = DiscuzReplyFormPreparationDataSource(
        cookieStore: cookieStore,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final preparation = await dataSource.fetchReplyPreparation(uri);

      expect(adapter.lastUri, uri);
      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastHeaders['cookie'], contains('reply_cookie=123'));
      expect(preparation.reference.noticeTrimStr, '[quote]引用[/quote]');
      final cookieHeader = await cookieStore.readCookieHeader(uri);
      expect(cookieHeader, contains('next_cookie=456'));
    });
  });
}

class _ReplyFormTestAdapter implements HttpClientAdapter {
  _ReplyFormTestAdapter({
    required this.html,
    this.headers = const <String, List<String>>{},
  });

  final String html;
  final Map<String, List<String>> headers;
  Uri lastUri = Uri();
  String lastMethod = '';
  Map<String, dynamic> lastHeaders = <String, dynamic>{};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    lastMethod = options.method;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    return ResponseBody.fromBytes(
      utf8.encode(html),
      200,
      headers: headers,
    );
  }
}

String _formHtml() {
  return '''
<form id="postform">
  <input type="hidden" name="formhash" value="prepared-formhash">
  <input type="hidden" name="noticetrimstr" value="[quote]引用[/quote]">
  <input type="hidden" name="noticeauthor" value="notice-token">
  <input type="hidden" name="noticeauthormsg" value="引用正文">
  <input type="hidden" name="reppid" value="41554317">
  <input type="hidden" name="reppost" value="41554317">
</form>
''';
}
