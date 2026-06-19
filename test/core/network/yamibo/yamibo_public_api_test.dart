import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo/yamibo.dart';

void main() {
  test('yamibo barrel exports public network boundary types', () {
    const context = YamiboRequestContext(
      kind: YamiboRequestKind.html,
      operation: 'test.operation',
      module: 'test',
      pageKind: 'smoke',
    );
    final snapshot = YamiboSessionSnapshot(
      isLoggedIn: true,
      uid: '123',
      username: 'reader',
      formhash: 'fh',
      updatedAt: DateTime.utc(2026, 6, 19),
      source: 'test',
    );
    final response = YamiboHttpResponse<String>(
      uri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
      statusCode: 200,
      headers: const <String, List<String>>{},
      body: '<html></html>',
    );

    expect(context.kind, YamiboRequestKind.html);
    expect(snapshot.formhash, 'fh');
    expect(response.body, '<html></html>');
    expect(YamiboSessionStore().readCurrent(), isNull);
    expect(const YamiboSessionExtractor(), isA<YamiboSessionExtractor>());
  });
}
