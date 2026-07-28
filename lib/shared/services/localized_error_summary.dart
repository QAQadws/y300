import 'package:y300/core/network/api_result.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class LocalizedErrorSummary {
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
    if (error is ApiError) {
      return switch (error.type) {
        ApiErrorType.network => l10n.commonNetworkError,
        ApiErrorType.timeout => l10n.commonTimeoutError,
        ApiErrorType.unauthorized => l10n.commonUnauthorizedError,
        ApiErrorType.server => l10n.commonServerError,
        ApiErrorType.parse => l10n.commonParseError,
        ApiErrorType.business => l10n.commonRequestError,
        ApiErrorType.unknown => l10n.commonUnknownError,
      };
    }
    final raw = switch (error) {
      StateError(:final message) => message,
      _ => error?.toString() ?? '',
    };
    var value = raw
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
