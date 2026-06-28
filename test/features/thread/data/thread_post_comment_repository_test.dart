import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/thread/data/repositories/thread_post_comment_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThreadPostCommentFormParser', () {
    test('parses desktop comment dialog form', () {
      final html = File('docs/html/帖子详细页/一个楼的点评功能.html').readAsStringSync();
      const parser = ThreadPostCommentFormParser();

      final form = parser.parse(
        html,
        fallbackCommentUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=572529&pid=41562047',
      );

      expect(form.actionUrl, contains('commentsubmit=yes'));
      expect(form.formHash, 'cba80c43');
      expect(form.handleKey, 'comment');
      expect(form.tid, '572529');
      expect(form.pid, '41562047');
      expect(form.referer, contains('viewthread'));
      expect(form.maxLength, 200);
    });

    test('parses cdata wrapped desktop comment dialog form', () {
      const html = '''
<root>
<![CDATA[ <form method="post" autocomplete="off" id="commentform" action="forum.php?mod=post&amp;action=reply&amp;comment=yes&amp;tid=570068&amp;pid=41518377&amp;extra=&amp;page=1&amp;commentsubmit=yes&amp;infloat=yes"> <div class="f_c"> <h3 class="flb"> <em id="return_comment">点评</em> </h3> <input type="hidden" name="formhash" id="formhash" value="cba80c43" /> <input type="hidden" name="handlekey" value="comment" /> <textarea rows="2" cols="50" name="message" id="commentmessage"></textarea> <span class="y">还可输入 <strong id="checklen">200</strong> 个字符</span> </div> </form> ]]>
</root>
''';
      const parser = ThreadPostCommentFormParser();

      final form = parser.parse(
        html,
        fallbackCommentUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=570068&pid=41518377',
      );

      expect(form.formHash, 'cba80c43');
      expect(form.handleKey, 'comment');
      expect(form.tid, '570068');
      expect(form.pid, '41518377');
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
                'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=570068&pid=41520485',
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
        final html = File('docs/html/帖子详细页/一个楼的点评功能.html').readAsStringSync();
        final adapter = _CommentFormTestAdapter(textBody: html);
        final repository = DiscuzThreadPostCommentRepository(
          gateway: _buildGateway(adapter),
        );

        final result = await repository.loadFormFromSeed(
          const ThreadPostCommentFormSeed(
            commentUrl: '',
            tid: '572529',
            pid: '41562047',
            page: 2,
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(adapter.lastUri?.queryParameters['mod'], 'misc');
        expect(adapter.lastUri?.queryParameters['action'], 'comment');
        expect(adapter.lastUri?.queryParameters['tid'], '572529');
        expect(adapter.lastUri?.queryParameters['pid'], '41562047');
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
