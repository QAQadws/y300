import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_request_logger.dart';

void main() {
  test('never writes sensitive URI values to success logs', () {
    final output = _MemoryLogOutput();
    final logger = YamiboRequestLogger(
      logger: Logger(output: output, level: Level.info),
    );

    logger.logSuccess(
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post_edit.delete_attachment',
      ),
      requestId: 'request-1',
      method: 'GET',
      uri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?formhash=secret&tid=10&token=secret-token',
      ),
      statusCode: 200,
      elapsedMs: 3,
      body: '<![CDATA[1]]>',
    );

    final text = output.lines.join('\n');
    expect(text, contains('tid=10'));
    expect(text, contains('formhash=%5BREDACTED%5D'));
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('<![CDATA[1]]>')));
  });

  test('silent contexts do not emit request logs', () {
    final output = _MemoryLogOutput();
    final logger = YamiboRequestLogger(
      logger: Logger(output: output, level: Level.info),
    );

    logger.logSuccess(
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post_edit.submit',
        silent: true,
      ),
      requestId: 'request-2',
      method: 'POST',
      uri: Uri.parse('https://bbs.yamibo.com/forum.php?formhash=secret'),
      statusCode: 200,
      elapsedMs: 3,
      body: 'String(length=10)',
    );

    expect(output.lines, isEmpty);
  });

  test('never writes sensitive URI values to failure logs', () {
    final output = _MemoryLogOutput();
    final logger = YamiboRequestLogger(
      logger: Logger(output: output, level: Level.warning),
    );

    logger.logFailure(
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post_edit.submit',
      ),
      requestId: 'request-3',
      method: 'POST',
      uri: Uri.parse(
        'https://user:password@bbs.yamibo.com/forum.php?uploadhash=secret-upload&tid=10',
      ),
      statusCode: 504,
      elapsedMs: 30,
      error: DioException(
        requestOptions: RequestOptions(path: '/forum.php'),
        type: DioExceptionType.connectionTimeout,
      ),
    );

    final text = output.lines.join('\n');
    expect(text, contains('tid=10'));
    expect(text, contains('uploadhash=%5BREDACTED%5D'));
    expect(text, isNot(contains('secret-upload')));
    expect(text, isNot(contains('user:password')));
  });
}

final class _MemoryLogOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) {
    lines.addAll(event.lines);
  }
}
