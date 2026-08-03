/// Strictly unwraps the XML envelope used by Discuz AJAX endpoints.
///
/// A normal HTML page, WAF challenge, or login response must not be accepted
/// as an empty AJAX payload because callers may use an empty payload as an
/// authoritative deletion signal.
final class DiscuzAjaxCdataParser {
  const DiscuzAjaxCdataParser();

  static final RegExp _envelopePattern = RegExp(
    r'^\uFEFF?\s*(?:<\?xml[^>]*\?>\s*)?<root\b[^>]*>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*</root>\s*$',
    caseSensitive: false,
  );

  String? extract(String body) {
    return _envelopePattern.firstMatch(body)?.group(1);
  }

  int? extractInteger(String body) {
    final payload = extract(body)?.trim();
    if (payload == null || payload.isEmpty) {
      return null;
    }
    return int.tryParse(payload);
  }
}
