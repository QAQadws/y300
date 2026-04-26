class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl =
      'https://bbs.yamibo.com/api/mobile/index.php';
  static const String defaultApiVersion = '4';
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
