import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo/yamibo_uri_redactor.dart';

void main() {
  const redactor = YamiboUriRedactor();

  test('redacts credentials while preserving safe query parameters', () {
    final redacted = redactor.redact(
      Uri.parse(
        'https://user:password@bbs.yamibo.com/forum.php?'
        'formhash=secret-formhash&tid=10&token=secret-token&tid=11',
      ),
    );

    expect(redacted.userInfo, isEmpty);
    expect(redacted.queryParametersAll['formhash'], ['[REDACTED]']);
    expect(redacted.queryParametersAll['token'], ['[REDACTED]']);
    expect(redacted.queryParametersAll['tid'], ['10', '11']);
    expect(redacted.toString(), isNot(contains('password')));
    expect(redacted.toString(), isNot(contains('secret-formhash')));
    expect(redacted.toString(), isNot(contains('secret-token')));
  });

  test('leaves ordinary request URIs unchanged', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10#pid11',
    );

    expect(redactor.redact(uri), uri);
  });

  test('redacts the opaque daily sign value regardless of query case', () {
    final redacted = redactor.redact(
      Uri.parse(
        'https://bbs.yamibo.com/plugin.php?id=zqlj_sign&Sign=opaque-fixture-value',
      ),
    );

    expect(redacted.queryParameters['Sign'], '[REDACTED]');
    expect(redacted.toString(), isNot(contains('opaque-fixture-value')));
    expect(redacted.queryParameters['id'], 'zqlj_sign');
  });
}
