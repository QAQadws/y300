import 'dart:convert';

enum WafChallengeEvidence { scriptBody, httpMethodNotAllowed }

/// A conservative classifier for the Aliyun `acw_sc__v2` browser challenge.
///
/// The explicit script signature is authoritative for every HTTP method. A
/// bare 405 is weaker evidence, so it is only treated as recoverable for GET
/// requests; replaying a mutation based on a status code alone is unsafe.
abstract final class WafChallengeDetector {
  static WafChallengeEvidence? detect({
    required Object? body,
    required int? statusCode,
    required String method,
  }) {
    if (isChallengeBody(body)) {
      return WafChallengeEvidence.scriptBody;
    }
    if (statusCode == 405 && method.trim().toUpperCase() == 'GET') {
      return WafChallengeEvidence.httpMethodNotAllowed;
    }
    return null;
  }

  static bool isChallengeBody(Object? body) {
    final text = _headAsText(body);
    if (text == null || text.isEmpty) {
      return false;
    }
    final normalized = text.trimLeft().toLowerCase();
    final scriptStart = normalized.indexOf('<script');
    final hasChallengeShell =
        (normalized.startsWith('<html') ||
            normalized.startsWith('<!doctype') ||
            normalized.startsWith('<script')) &&
        scriptStart >= 0 &&
        scriptStart <= 512;
    if (!hasChallengeShell) {
      return false;
    }
    final scriptEnd = normalized.indexOf('</script>', scriptStart);
    final script = normalized.substring(
      scriptStart,
      scriptEnd < 0 ? normalized.length : scriptEnd,
    );
    return _arg1Pattern.hasMatch(script) ||
        (script.contains('document.cookie') && script.contains('acw_sc__v2'));
  }

  static String? _headAsText(Object? body) {
    if (body is String) {
      return body.length <= _sniffLimit ? body : body.substring(0, _sniffLimit);
    }
    if (body is List<int>) {
      if (body.isEmpty) {
        return null;
      }
      final length = body.length < _sniffLimit ? body.length : _sniffLimit;
      return latin1.decode(body.sublist(0, length), allowInvalid: true);
    }
    return null;
  }

  static final RegExp _arg1Pattern = RegExp(
    r'''\bvar\s+arg1\s*=\s*['\"]''',
    caseSensitive: false,
  );

  static const int _sniffLimit = 8192;
}
