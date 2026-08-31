import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/src/parsing/strict_json.dart';

void main() {
  test('strict parser rejects malformed values with stable code only', () {
    expect(
      () => StrictJson.integer('not-a-number', code: 'count_invalid'),
      throwsA(
        isA<DataParseException>().having(
          (e) => e.code,
          'code',
          'count_invalid',
        ),
      ),
    );
  });
}
