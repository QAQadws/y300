import 'package:y300/core/config/app_config.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

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
    ForumReferenceResolver references = const ForumReferenceResolver(),
  }) : _references = references;

  final ForumReferenceResolver _references;

  String? normalizeOverride(String? rawUrl) {
    final value = rawUrl?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.invalidUrl,
      );
    }
    if (parsed.isAbsolute &&
        parsed.scheme != 'http' &&
        parsed.scheme != 'https') {
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.unsupportedScheme,
      );
    }
    final uri = _references.resolveSameSite(value);
    if (uri == null) {
      if (parsed.isAbsolute && parsed.host.isNotEmpty) {
        final siteUri = Uri.parse(AppConfig.siteBaseUrl);
        throw ComicCatalogUrlInputException(
          ComicCatalogUrlInputErrorCode.unexpectedHost,
          expectedHost: siteUri.host,
        );
      }
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.incompleteUrl,
      );
    }

    final siteUri = Uri.parse(AppConfig.siteBaseUrl);
    if (uri.host.toLowerCase() != siteUri.host.toLowerCase()) {
      throw ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.unexpectedHost,
        expectedHost: siteUri.host,
      );
    }
    if (!_references.isTagCatalogUrl(uri.toString())) {
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.notTagCatalog,
      );
    }
    final normalized = _references.normalizeTagPageReference(uri.toString());
    if (normalized == null) {
      throw const ComicCatalogUrlInputException(
        ComicCatalogUrlInputErrorCode.invalidUrl,
      );
    }
    return Uri.parse(normalized).removeFragment().toString();
  }
}
