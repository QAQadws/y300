import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final zhTw = lookupAppLocalizations(const Locale('zh', 'TW'));

  test('maps structured API errors using the active locale', () {
    const error = ApiError(
      type: ApiErrorType.timeout,
      message: 'diagnostic.timeout',
    );

    expect(LocalizedErrorSummary.resolve(zh, error), '请求超时');
    expect(LocalizedErrorSummary.resolve(zhTw, error), '請求逾時');
  });

  test('redacts secrets, flattens lines, and limits unknown details', () {
    final detail = StateError(
      'request https://bbs.yamibo.com/path?token=secret\n'
      'formhash=abc123\n'
      'uploadHash=def456\n'
      'Cookie=session-secret\n'
      '${List.filled(220, 'x').join()}',
    );

    final summary = LocalizedErrorSummary.resolve(zh, detail);

    expect(summary, isNot(contains('https://')));
    expect(summary, isNot(contains('abc123')));
    expect(summary, isNot(contains('def456')));
    expect(summary, isNot(contains('session-secret')));
    expect(summary, isNot(contains('\n')));
    expect(summary.runes.length, lessThanOrEqualTo(160));
  });
}
