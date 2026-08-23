import 'package:html/parser.dart' as html_parser;

abstract final class DiscuzProfileAuthPageDetector {
  static bool isLoginPage(String html) {
    final document = html_parser.parse(html);
    return document.querySelector(
          'form#loginform, form[name="login"], .loginbox',
        ) !=
        null;
  }
}
