import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';

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
      throw const FormatException('目录 URL 格式无效');
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('请输入完整的目录 URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('目录 URL 仅支持 http 或 https');
    }

    final siteUri = Uri.parse(AppConfig.siteBaseUrl);
    if (uri.host.toLowerCase() != siteUri.host.toLowerCase()) {
      throw FormatException('目录 URL 必须来自 ${siteUri.host}');
    }
    if (!_tagPageParsing.isTagCatalogUrl(uri.toString())) {
      throw const FormatException('请输入 Yamibo 标签目录 URL');
    }
    return uri.removeFragment().toString();
  }
}
