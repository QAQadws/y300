import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/tags/data/services/yamibo_tag_thread_page_html_parser.dart';
import 'package:y300/features/tags/domain/models/yamibo_tag_thread_page.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';

abstract class YamiboTagThreadPageRepository {
  Future<ApiResult<YamiboTagThreadPageData>> load(String url);
}

class HtmlYamiboTagThreadPageRepository
    implements YamiboTagThreadPageRepository {
  const HtmlYamiboTagThreadPageRepository({
    required YamiboHtmlClient htmlClient,
    YamiboTagThreadPageHtmlParser parser =
        const YamiboTagThreadPageHtmlParser(),
    YamiboTagPageParsing tagPageParsing = const YamiboTagPageParsing(),
  }) : _htmlClient = htmlClient,
       _parser = parser,
       _tagPageParsing = tagPageParsing;

  final YamiboHtmlClient _htmlClient;
  final YamiboTagThreadPageHtmlParser _parser;
  final YamiboTagPageParsing _tagPageParsing;

  @override
  Future<ApiResult<YamiboTagThreadPageData>> load(String url) async {
    final normalized = _tagPageParsing.normalizeCatalogEntryUrl(url);
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return const ApiFailure<YamiboTagThreadPageData>(
        ApiError(type: ApiErrorType.business, message: '标签页地址无效'),
      );
    }
    final htmlResult = await _htmlClient.getDesktopPage(
      path: uri.path.isEmpty ? '/misc.php' : uri.path,
      queryParameters: uri.queryParameters,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'tag.threadPage',
        pageKind: 'tag.threadPage',
      ),
    );
    if (htmlResult case ApiFailure<String>(:final error)) {
      return ApiFailure<YamiboTagThreadPageData>(
        ApiError(
          type: error.type,
          message: '标签页 HTML 加载失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      );
    }

    try {
      return ApiSuccess<YamiboTagThreadPageData>(
        _parser.parse(html: htmlResult.dataOrNull ?? '', pageUrl: normalized),
      );
    } catch (error) {
      return ApiFailure<YamiboTagThreadPageData>(
        ApiError(
          type: ApiErrorType.parse,
          message: '标签页 HTML 解析失败: $error',
          raw: error,
        ),
      );
    }
  }
}
