/// 阿里云 WAF 通行证响应式恢复模块。
///
/// 出口：
/// - [WafChallengeDetector]：判定响应正文是否为 WAF 挑战页
/// - [WafChallengePasser]：抽象接口——在真实浏览器中触发挑战脚本
/// - [HeadlessInAppWebViewChallengePasser]：默认实现（headless WebView）
/// - [WafChallengeResolver]：单例协调器，负责去重、放行窗口与 cookie 同步
///
/// 单元测试通过替换 [WafChallengePasser] 屏蔽 WebView 平台通道；生产环境由
/// `network_providers.dart` 注入默认实现。
library;

export 'waf_challenge_detector.dart';
export 'waf_challenge_passer.dart';
export 'waf_challenge_resolver.dart';
