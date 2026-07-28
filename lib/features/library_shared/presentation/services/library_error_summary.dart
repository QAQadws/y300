import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/features/library_shared/domain/models/library_operation_failure.dart';

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
    if (error is LibraryOperationException) {
      return switch (error.code) {
        LibraryOperationFailureCode.workNotFound =>
          l10n.libraryOperationWorkNotFound,
        LibraryOperationFailureCode.chapterNotFound =>
          l10n.libraryOperationChapterNotFound,
        LibraryOperationFailureCode.unsupported =>
          l10n.libraryOperationUnsupported,
        LibraryOperationFailureCode.cacheWriteFailed =>
          l10n.libraryOperationCacheWriteFailed,
        LibraryOperationFailureCode.defaultCategoryImmutable =>
          l10n.libraryOperationDefaultCategoryImmutable,
      };
    }
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
