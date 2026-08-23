import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/tags/data/services/discuz_tag_directory_html_parser.dart';
import 'package:y300/features/tags/domain/models/forum_tag_directory_models.dart';
import 'package:y300/features/tags/domain/repositories/forum_tag_directory_repository.dart';

final class DiscuzForumTagDirectoryRepository
    implements ForumTagDirectoryRepository {
  const DiscuzForumTagDirectoryRepository({
    required YamiboHtmlClient htmlClient,
    DiscuzTagDirectoryHtmlParser parser = const DiscuzTagDirectoryHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final DiscuzTagDirectoryHtmlParser _parser;

  @override
  ForumTagDirectorySourceCapabilities get capabilities => _htmlCapabilities;

  @override
  Future<
    DataReadResult<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>
  >
  load(
    ForumTagDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    // This adapter has no document or snapshot cache. Both policies therefore
    // intentionally perform one network read.
    final tagId = query.tagId.trim();
    if (tagId.isEmpty || query.page < 1) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_tag_directory_query_invalid',
        diagnosticMessage: 'Tag directory query is invalid.',
      );
    }

    final queryParameters = <String, String>{
      'mod': 'tag',
      'id': tagId,
      'type': 'thread',
      if (query.page > 1) 'page': query.page.toString(),
    };
    final htmlResult = await _htmlClient.getDesktopPage(
      path: '/misc.php',
      queryParameters: queryParameters,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'tag.directory.html',
        pageKind: 'tag.directory',
      ),
    );
    if (htmlResult case ApiFailure<String>(:final error)) {
      return dataReadFailureFromApiError<
        ForumTagDirectoryData,
        ForumTagDirectoryReadCapabilities
      >(error);
    }

    try {
      final data = _parser.parse(
        html: htmlResult.dataOrNull ?? '',
        pageUrl: _buildPageUrl(queryParameters),
        expectedTagId: tagId,
        requestedPage: query.page,
      );
      return _validatedSuccess(query: query, data: data);
    } catch (error) {
      return DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_tag_directory_parse_failed',
        diagnosticMessage: 'Tag directory HTML parsing failed: $error',
      );
    }
  }

  DataReadResult<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>
  _validatedSuccess({
    required ForumTagDirectoryQuery query,
    required ForumTagDirectoryData data,
  }) {
    if (data.tag.id.trim() != query.tagId.trim() ||
        data.pagination.currentPage != query.page) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_tag_directory_identity_mismatch',
        diagnosticMessage: 'Tag directory identity does not match the query.',
      );
    }
    final topicIds = <String>{};
    for (final topic in data.topics) {
      if (topic.tid.trim().isEmpty ||
          topic.title.trim().isEmpty ||
          !topicIds.add(topic.tid.trim())) {
        return const DataReadFailure(
          kind: DataReadFailureKind.parse,
          code: 'forum_tag_directory_topic_identity_invalid',
          diagnosticMessage: 'Tag directory contains invalid topic identity.',
        );
      }
    }
    final totalPages = data.pagination.totalPages;
    if (totalPages != null &&
        (totalPages < 1 || data.pagination.currentPage > totalPages)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_tag_directory_pagination_invalid',
        diagnosticMessage: 'Tag directory pagination is invalid.',
      );
    }
    final readCapabilities = _readCapabilitiesFor(data);
    return DataReadSuccess(
      data: data,
      capabilities: readCapabilities,
      metadata: const DataReadMetadata.network(),
    );
  }

  String _buildPageUrl(Map<String, String> queryParameters) {
    return Uri.parse(
      AppConfig.siteBaseUrl,
    ).replace(path: '/misc.php', queryParameters: queryParameters).toString();
  }

  ForumTagDirectoryReadCapabilities _readCapabilitiesFor(
    ForumTagDirectoryData data,
  ) {
    final pagination = data.pagination;
    final hasDirectionalEvidence =
        pagination.hasPrevious != null || pagination.hasNext != null;
    final topics = data.topics;
    DataCapabilitySupport supportWhen(bool value) => value
        ? DataCapabilitySupport.supported
        : DataCapabilitySupport.unsupported;
    final values = _htmlCapabilities.values
        .withSupport(
          ForumTagDirectoryCapability.tagName,
          supportWhen(data.tag.name?.trim().isNotEmpty == true),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicForum,
          supportWhen(
            topics.any(
              (topic) =>
                  topic.forumId?.trim().isNotEmpty == true ||
                  topic.forumName?.trim().isNotEmpty == true,
            ),
          ),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicAuthor,
          supportWhen(
            topics.any(
              (topic) =>
                  topic.authorId?.trim().isNotEmpty == true ||
                  topic.authorName?.trim().isNotEmpty == true,
            ),
          ),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicCreationTime,
          supportWhen(topics.any((topic) => topic.createdAt != null)),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicReplyCount,
          supportWhen(topics.any((topic) => topic.replyCount != null)),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicViewCount,
          supportWhen(topics.any((topic) => topic.viewCount != null)),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicLastPost,
          supportWhen(
            topics.any(
              (topic) =>
                  topic.lastPosterName != null || topic.lastPostAt != null,
            ),
          ),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicAttachmentFlags,
          supportWhen(
            topics.any(
              (topic) =>
                  topic.hasImageAttachment != null ||
                  topic.hasAttachment != null,
            ),
          ),
        )
        .withSupport(
          ForumTagDirectoryCapability.directionalPagination,
          hasDirectionalEvidence
              ? DataCapabilitySupport.supported
              : DataCapabilitySupport.unsupported,
        )
        .withSupport(
          ForumTagDirectoryCapability.totalPageCount,
          pagination.totalPages != null
              ? DataCapabilitySupport.supported
              : DataCapabilitySupport.unsupported,
        );
    return ForumTagDirectoryReadCapabilities(
      values: values,
      paginationPrecision: pagination.totalPages != null
          ? PaginationPrecision.exact
          : hasDirectionalEvidence
          ? PaginationPrecision.directional
          : PaginationPrecision.unknown,
    );
  }
}

final _htmlCapabilities = ForumTagDirectorySourceCapabilities(
  values: DataCapabilitySet<ForumTagDirectoryCapability>.supported(
    ForumTagDirectoryCapability.values,
  ),
  paginationPrecision: PaginationPrecision.unknown,
);
