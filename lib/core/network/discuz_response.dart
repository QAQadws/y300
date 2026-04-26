import 'package:y300/core/utils/parse_utils.dart';

/// Discuz 移动接口通用响应结构
class DiscuzResponse {
  DiscuzResponse({
    required this.version,
    required this.charset,
    required this.variables,
    this.message,
  });

  final String version;
  final String charset;
  final JsonMap variables;
  final JsonMap? message;

  factory DiscuzResponse.fromJson(JsonMap json) {
    final messageNode = ParseUtils.asMap(json['Message']);
    return DiscuzResponse(
      version: ParseUtils.asString(json['Version']),
      charset: ParseUtils.asString(json['Charset']),
      variables: ParseUtils.asMap(json['Variables']),
      message: messageNode.isEmpty ? null : messageNode,
    );
  }

  /// Discuz 约定：出现 Message 节点通常代表业务失败
  bool get hasBusinessError => message != null;

  String get businessMessage {
    final rawMessage = ParseUtils.asString(message?['messagestr']);
    if (rawMessage.isNotEmpty) {
      return rawMessage;
    }
    return ParseUtils.asString(message?['messageval'], fallback: '业务请求失败');
  }

  String get businessCode {
    return ParseUtils.asString(message?['messageval'], fallback: 'biz_error');
  }
}
