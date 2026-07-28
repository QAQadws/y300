import 'dart:convert';

import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 发帖接口响应解析。
///
/// Discuz `module=newthread` 成功响应的两种形态：
/// 1. `Variables.tid` + `Variables.pid` 同时存在；`Message.messageval` 为
///    `post_newthread_succeed` 或包含 `succeed`。
/// 2. 极少数情况下 `Variables.tid` 缺失，但 `Message.messageval` 表示成功。
///
/// 解析失败时把 `messageval` 原样回传，由领域分类器归一为稳定失败 code，
/// presentation 再按当前 locale 映射为用户可见文案。
class NewThreadResponseParser {
  const NewThreadResponseParser();

  NewThreadParseResult parse(dynamic data) {
    final root = _asJsonMap(data);
    final variables = ParseUtils.asMap(root['Variables']);
    final messageNode = ParseUtils.asMap(root['Message']);

    final tid = ParseUtils.asString(variables['tid']);
    final pid = ParseUtils.asString(variables['pid']);
    final messageVal = ParseUtils.asString(
      messageNode['messageval'],
      fallback: '',
    );
    final messageStr = ParseUtils.asString(
      messageNode['messagestr'],
      fallback: messageVal,
    );
    final loweredVal = messageVal.toLowerCase();
    final loweredStr = messageStr.toLowerCase();

    final messagePositive =
        loweredVal == 'post_newthread_succeed' ||
        loweredVal.contains('succeed') ||
        loweredVal.contains('success') ||
        loweredStr.contains('成功');

    if (tid.isNotEmpty &&
        pid.isNotEmpty &&
        (messagePositive || messageVal.isEmpty)) {
      return NewThreadParseResult.success(
        result: NewThreadSubmissionResult(
          tid: tid,
          pid: pid,
          message: messageStr,
        ),
      );
    }
    if (messagePositive && tid.isNotEmpty) {
      return NewThreadParseResult.success(
        result: NewThreadSubmissionResult(
          tid: tid,
          pid: pid,
          message: messageStr,
        ),
      );
    }

    return NewThreadParseResult.failure(code: messageVal, message: messageStr);
  }

  Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return ParseUtils.asMap(decoded);
      } on FormatException {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }
}

class NewThreadParseResult {
  const NewThreadParseResult._({
    required this.success,
    this.result,
    this.code = '',
    this.message = '',
  });

  const NewThreadParseResult.success({
    required NewThreadSubmissionResult result,
  }) : this._(success: true, result: result);

  const NewThreadParseResult.failure({
    required String code,
    required String message,
  }) : this._(success: false, code: code, message: message);

  final bool success;
  final NewThreadSubmissionResult? result;
  final String code;
  final String message;
}
