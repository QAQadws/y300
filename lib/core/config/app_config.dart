class AppConfig {
  const AppConfig._();

  // Discuz 站点根地址，用于网页登录与页面级接口。
  static const String siteBaseUrl = 'https://bbs.yamibo.com';
  static const String apiBaseUrl =
      'https://bbs.yamibo.com/api/mobile/index.php';
  static const String defaultApiVersion = '4';
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
