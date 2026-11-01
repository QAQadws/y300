import 'package:flutter/painting.dart' show Locale;

/// The native Locale port represents language, script and region. Do not
/// silently truncate variants/extensions or reinterpret non-BCP47 spellings.
final _nativeTag = RegExp(
  r'^([A-Za-z]{2,8})(?:-([A-Za-z]{4}))?(?:-([A-Za-z]{2}|[0-9]{3}))?$',
);

Locale? resolveForumBodyLanguage({
  required Map<String, String> attributes,
  required Locale? inherited,
  required void Function(String value) onUnsupported,
}) {
  final tag = attributes['lang'];
  // A literal, non-namespaced xml:lang on HTML has no language-processing
  // effect. The parser owns HTML fragments, not an XML language namespace.
  if (tag == null) return inherited;
  if (tag.isEmpty) return const Locale('und');
  final match = _nativeTag.firstMatch(tag);
  if (match == null || match.end != tag.length) {
    onUnsupported(tag);
    return const Locale('und');
  }
  final script = match[2];
  return Locale.fromSubtags(
    languageCode: match[1]!.toLowerCase(),
    scriptCode: script == null
        ? null
        : script[0].toUpperCase() + script.substring(1).toLowerCase(),
    countryCode: match[3]?.toUpperCase(),
  );
}
