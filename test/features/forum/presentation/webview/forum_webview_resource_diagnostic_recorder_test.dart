import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_resource_diagnostic_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_resource_diagnostic_recorder.dart';

void main() {
  test('recorder logs targeted resource failures in debug mode', () {
    final messages = <String>[];
    final recorder = DefaultForumWebViewResourceDiagnosticRecorder(
      writeLog: messages.add,
      isDebugMode: true,
    );

    recorder.record(
      ForumWebViewResourceDiagnosticEvent(
        uri: Uri.parse('https://bbs.yamibo.com/static/image/smiley/1.gif'),
        kind: ForumWebViewResourceKind.smiley,
        statusCode: 404,
        errorDescription: 'Not Found',
        isMainFrame: false,
      ),
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains('[smiley]'));
    expect(messages.single, contains('status=404'));
  });

  test('recorder skips non-debug or non-targeted noise', () {
    final messages = <String>[];
    final recorder = DefaultForumWebViewResourceDiagnosticRecorder(
      writeLog: messages.add,
      isDebugMode: false,
    );

    recorder.record(
      ForumWebViewResourceDiagnosticEvent(
        uri: Uri.parse('https://bbs.yamibo.com/static/image/smiley/1.gif'),
        kind: ForumWebViewResourceKind.smiley,
        statusCode: 404,
        errorDescription: 'Not Found',
        isMainFrame: false,
      ),
    );
    recorder.record(
      ForumWebViewResourceDiagnosticEvent(
        uri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
        kind: ForumWebViewResourceKind.other,
        isMainFrame: true,
      ),
    );

    expect(messages, isEmpty);
  });
}
