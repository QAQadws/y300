import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/thread/data/repositories/thread_post_comment_repository.dart';

import '../../../test_support/utf8_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThreadPostCommentFormParser', () {
    test('parses desktop comment dialog form', () {
      final html = readUtf8TestFixture('thread/actions/comment_form.html');
      const parser = ThreadPostCommentFormParser();

      final form = parser.parse(
        html,
        fallbackCommentUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=10001&pid=20001',
      );

      expect(form.actionUrl, contains('commentsubmit=yes'));
      expect(form.formHash, 'fixture-formhash');
      expect(form.handleKey, 'comment');
      expect(form.tid, '10001');
      expect(form.pid, '20001');
      expect(form.referer, contains('viewthread'));
      expect(form.maxLength, 200);
    });

    test('parses cdata wrapped desktop comment dialog form', () {
      const html = '''
<root>
<![CDATA[
<form id="commentform" action="forum.php?mod=post&amp;action=reply&amp;comment=yes&amp;tid=10001&amp;pid=20001&amp;commentsubmit=yes">
  <input name="formhash" value="fixture-formhash">
  <input name="handlekey" value="comment">
  <textarea name="message"></textarea>
  <strong id="checklen">200</strong>
</form>
]]>
</root>
''';
      const parser = ThreadPostCommentFormParser();

      final form = parser.parse(
        html,
        fallbackCommentUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=10001&pid=20001',
      );

      expect(form.formHash, 'fixture-formhash');
      expect(form.handleKey, 'comment');
      expect(form.tid, '10001');
      expect(form.pid, '20001');
    });

    test(
      'reports cdata wrapped permission prompt when comment form is absent',
      () {
        const html = '''
<root>
<![CDATA[ <h3 class="flb"><em>提示信息</em></h3> <div class="c altw"> <div class="alert_error">抱歉，您不能点评此帖或帖子尚未找到<script type="text/javascript">if(typeof errorhandle_comment=='function') {errorhandle_comment('抱歉，您不能点评此帖或帖子尚未找到', {});}</script></div> </div> ]]>
</root>
''';
        const parser = ThreadPostCommentFormParser();

        expect(
          () => parser.parse(
            html,
            fallbackCommentUrl:
                'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=10001&pid=20001',
          ),
          throwsA(
            isA<ThreadPostCommentFormParseException>().having(
              (error) => error.message,
              'message',
              contains('不能点评此帖'),
            ),
          ),
        );
      },
    );
  });

  group('DiscuzThreadPostCommentRepository', () {
    test(
      'builds comment form endpoint from seed for posts without action link',
      () async {
        final html = readUtf8TestFixture('thread/actions/comment_form.html');
        final adapter = _CommentFormTestAdapter(textBody: html);
        final repository = DiscuzThreadPostCommentRepository(
          gateway: _buildGateway(adapter),
        );

        final result = await repository.loadFormFromSeed(
          const ThreadPostCommentFormSeed(
            commentUrl: '',
            tid: '10001',
            pid: '20001',
            page: 2,
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(adapter.lastUri?.queryParameters['mod'], 'misc');
        expect(adapter.lastUri?.queryParameters['action'], 'comment');
        expect(adapter.lastUri?.queryParameters['tid'], '10001');
        expect(adapter.lastUri?.queryParameters['pid'], '20001');
        expect(adapter.lastUri?.queryParameters['extra'], '');
        expect(adapter.lastUri?.queryParameters['page'], '2');
        expect(adapter.lastUri?.queryParameters['infloat'], 'yes');
        expect(adapter.lastUri?.queryParameters['handlekey'], 'comment');
        expect(adapter.lastUri?.queryParameters['inajax'], '1');
        expect(
          adapter.lastUri?.queryParameters['ajaxtarget'],
          'fwin_content_comment',
        );
        expect(adapter.lastHeaders['User-Agent'], contains('Windows NT 10.0'));
      },
    );
  });
}

YamiboHttpGateway _buildGateway(_CommentFormTestAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(
      printer: SimplePrinter(colors: false),
      output: _SilentLogOutput(),
      filter: ProductionFilter(),
    ),
    dio: dio,
    enableLog: false,
  );
}

class _CommentFormTestAdapter implements HttpClientAdapter {
  _CommentFormTestAdapter({required this.textBody});

  final String textBody;
  Map<String, dynamic> lastHeaders = const <String, dynamic>{};
  Uri? lastUri;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastHeaders = options.headers;
    lastUri = options.uri;
    return ResponseBody.fromString(
      textBody,
      200,
      headers: const <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }
}

class _SilentLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}
