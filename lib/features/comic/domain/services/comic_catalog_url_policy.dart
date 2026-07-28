import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';

enum ComicCatalogUrlInputErrorCode {
  invalidUrl,
  incompleteUrl,
  unsupportedScheme,
  unexpectedHost,
  notTagCatalog,
}

class ComicCatalogUrlInputException implements Exception {
  const ComicCatalogUrlInputException(this.code, {this.expectedHost});

  final ComicCatalogUrlInputErrorCode code;
  final String? expectedHost;

  @override
  String toString() => 'ComicCatalogUrlInputException(${code.name})';
}

/// Validates and normalizes catalog URLs entered by users.
///
/// The catalog fetcher always uses the Yamibo authenticated HTML client, so
/// accepting another host would display one URL while requesting another.
class ComicCatalogUrlPolicy {
  const ComicCatalogUrlPolicy({
    YamiboTagPageParsing tagPageParsing = const YamiboTagPageParsing(),
  }) : _tagPageParsing = tagPageParsing;

  final YamiboTagPageParsing _tagPageParsing;

  String? normalizeOverride(String? rawUrl) {
    final value = rawUrl?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    late final String normalized;
    try {
      normalized = _tagPageParsing.normalizeCatalogEntryUrl(value);
    } on FormatException {
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.invalidUrl,
      );
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.incompleteUrl,
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.unsupportedScheme,
      );
    }

    final siteUri = Uri.parse(AppConfig.siteBaseUrl);
    if (uri.host.toLowerCase() != siteUri.host.toLowerCase()) {
      throw ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.unexpectedHost,
        expectedHost: siteUri.host,
      );
    }
    if (!_tagPageParsing.isTagCatalogUrl(uri.toString())) {
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.notTagCatalog,
      );
    }
    return uri.removeFragment().toString();
  }
}
