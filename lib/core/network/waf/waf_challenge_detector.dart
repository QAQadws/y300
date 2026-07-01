/// 检测阿里云 WAF 挑战响应的纯函数。
///
/// 触发条件：论坛 CDN 前置的阿里云 WAF 在识别到"非浏览器"请求时，会以
/// HTTP 200 返回一段 JavaScript 挑战脚本代替真实内容。脚本形如：
///
/// ```html
/// <html><script>var arg1='...'; (function(a,c){var G=aOj,...})();</script></html>
/// ```
///
/// 脚本执行后会通过 `document.cookie='acw_sc__v2=<hash>'` 写入通行证 cookie，
/// 之后 30 分钟内的请求（在同一 IP/UA）不会再被挑战。原生 dio 无法执行脚本，
/// 从而拿到"HTTP 200 + 无效正文"的假成功——上游解析器要么抛 JSON 异常、
/// 要么把 HTML 当成空搜索结果，产生"某些版块乱码 / 搜索无结果 / 头像随机
/// 失败"这类看似无关的症状。
///
/// 这个模块只负责判定"看起来像挑战"。真正的通行证获取与请求重发由
/// [WafChallengeResolver] 与 [YamiboHttpGateway] 协调完成。
///
/// 判定策略是保守的：需要同时出现"HTML 外壳 + `<script>` 标签"与"WAF 特征
/// 关键字"，避免误判正常帖子/搜索页面（可能顺带包含 `arg1` 等普通字符串）。
abstract final class WafChallengeDetector {
  /// 判定 [body] 是否为阿里云 WAF 挑战正文。
  ///
  /// - [body] 支持 [String]（HTML/JSON）与 `List<int>`（bytes，用于图片/资源
  ///   请求，只解码前 4KiB ASCII 用于检测，避免拉长热路径）；其它类型一律返回
  ///   `false`。
  /// - 检测只看正文内容，不依赖 status code 或 content-type：WAF 挑战永远是
  ///   HTTP 200 + `text/html`，但 dio 层的 caller 可能期望 JSON。
  static bool isChallenge(Object? body) {
    if (body is String) {
      return _matches(body);
    }
    if (body is List<int>) {
      if (body.isEmpty) {
        return false;
      }
      // 只取前 4KiB 用于文本嗅探——挑战脚本在几百字节内即可完整识别。
      final head = body.length <= _byteSniffLimit
          ? body
          : body.sublist(0, _byteSniffLimit);
      final text = String.fromCharCodes(head.where(_isPrintableAsciiByte));
      return _matches(text);
    }
    return false;
  }

  static bool _matches(String body) {
    if (body.isEmpty) {
      return false;
    }
    // 只嗅探开头一段，避免长 HTML 全文扫描；同时排除多数正常响应。
    final head = body.length <= _headSniffLimit
        ? body
        : body.substring(0, _headSniffLimit);
    final lower = head.toLowerCase();

    // 结构性特征：HTML 外壳 + 内联 <script>。正常 mobile=2 帖子 JSON 不会
    // 命中；正常 HTML 页面也几乎不会把 <script> 放在最前几百字节。
    final hasHtmlShellWithScript =
        (lower.startsWith('<html') || lower.startsWith('<!doctype') ||
                lower.startsWith('<script')) &&
            lower.contains('<script');
    if (!hasHtmlShellWithScript) {
      return false;
    }

    // 关键字特征：`arg1='...'` 或 `acw_sc__v2` 关键字。任一命中即视为挑战。
    // - `arg1=` 是 WAF v2 挑战脚本的固定入口变量名。
    // - `acw_sc__v2` 出现在 `document.cookie` 赋值语句里。
    return _arg1Pattern.hasMatch(head) || lower.contains('acw_sc__v2');
  }

  static bool _isPrintableAsciiByte(int byte) {
    // 排除高位字节（gzip/图像流），保留 tab/换行/可打印字符。
    return byte == 0x09 || byte == 0x0A || byte == 0x0D ||
        (byte >= 0x20 && byte < 0x7F);
  }

  // `var arg1='...'`（允许可选空白与引号），匹配 WAF 挑战脚本第一行的常见形式。
  static final RegExp _arg1Pattern = RegExp(
    r'\bvar\s+arg1\s*=\s*[' "'\"" ']',
    caseSensitive: false,
  );

  // 4 KiB 足够覆盖挑战脚本第一屏；长文档只嗅探前段避免退化。
  static const int _headSniffLimit = 4096;
  static const int _byteSniffLimit = 4096;
}
