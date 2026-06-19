import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';

class YamiboSessionExtractor {
  const YamiboSessionExtractor({DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  YamiboSessionSnapshot? extractFromApiVariables(
    Map<String, dynamic> variables, {
    required String source,
  }) {
    final uid = _firstNonEmpty([
      ParseUtils.asString(variables['member_uid']),
      ParseUtils.asString(ParseUtils.asMap(variables['space'])['uid']),
    ]);
    final username = _firstNonEmpty([
      ParseUtils.asString(variables['member_username']),
      ParseUtils.asString(ParseUtils.asMap(variables['space'])['username']),
    ]);
    final formhash = ParseUtils.asString(variables['formhash']).trim();
    final auth = ParseUtils.asString(variables['auth']).trim();
    final isLoggedIn = uid.isNotEmpty && uid != '0' || auth.isNotEmpty;

    if (uid.isEmpty && username.isEmpty && formhash.isEmpty && auth.isEmpty) {
      return null;
    }
    return YamiboSessionSnapshot(
      isLoggedIn: isLoggedIn,
      uid: uid,
      username: username,
      formhash: formhash,
      updatedAt: _resolveNow(),
      source: source,
    );
  }

  YamiboSessionSnapshot? extractFromHtml(
    String html, {
    required String source,
  }) {
    if (html.trim().isEmpty) {
      return null;
    }
    final document = html_parser.parse(html);
    final formhash = _firstNonEmpty([
      for (final input in document.querySelectorAll('input[name="formhash"]'))
        input.attributes['value'] ?? '',
      _extractScriptAssignment(html, 'formhash'),
    ]);
    final uid = _firstNonEmpty([_extractScriptAssignment(html, 'discuz_uid')]);
    final username = _firstNonEmpty([
      _extractScriptAssignment(html, 'member_username'),
    ]);

    final hasLoginLink =
        document.querySelector('a[href*="logging"][href*="login"]') != null;
    final isLoggedIn = uid.isNotEmpty && uid != '0' || username.isNotEmpty;

    if (uid.isEmpty && username.isEmpty && formhash.isEmpty && !hasLoginLink) {
      return null;
    }
    return YamiboSessionSnapshot(
      isLoggedIn: isLoggedIn,
      uid: uid,
      username: username,
      formhash: formhash,
      updatedAt: _resolveNow(),
      source: source,
    );
  }

  DateTime _resolveNow() {
    return (_now ?? DateTime.now)();
  }

  String _firstNonEmpty(Iterable<String> values) {
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  String _extractScriptAssignment(String html, String name) {
    final pattern = RegExp(
      "${RegExp.escape(name)}\\s*=\\s*['\"]([^'\"]*)['\"]",
      caseSensitive: false,
    );
    return pattern.firstMatch(html)?.group(1)?.trim() ?? '';
  }
}
