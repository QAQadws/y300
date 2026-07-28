import 'package:y300/l10n/app_localizations.dart';

abstract final class LibraryErrorSummary {
  static const int maxLength = 160;

  static final RegExp _urlPattern = RegExp(
    r'https?://\S+',
    caseSensitive: false,
  );
  static final RegExp _cookiePattern = RegExp(
    r'\bcookie\b\s*[:=]\s*[^\r\n]*',
    caseSensitive: false,
  );
  static final RegExp _secretPattern = RegExp(
    r'\b(?:formhash|uploadhash)\b\s*[:=]\s*[^\s,;]+',
    caseSensitive: false,
  );
  static final RegExp _whitespacePattern = RegExp(r'\s+');

  static String resolve(AppLocalizations l10n, Object? error) {
    var value = error?.toString() ?? '';
    value = value
        .replaceAll(_urlPattern, l10n.libraryErrorRedactedLink)
        .replaceAll(_cookiePattern, l10n.libraryErrorRedactedSecret)
        .replaceAll(_secretPattern, l10n.libraryErrorRedactedSecret)
        .replaceAll(_whitespacePattern, ' ')
        .trim();
    if (value.isEmpty) {
      return l10n.commonUnknownError;
    }
    final runes = value.runes.toList(growable: false);
    if (runes.length <= maxLength) {
      return value;
    }
    const suffix = '...';
    return '${String.fromCharCodes(runes.take(maxLength - suffix.length))}$suffix';
  }
}
