import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_tag_directory.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_tag_directory_html_parser.dart';

final class DiscuzForumTagDirectoryRepository
    implements ForumTagDirectoryRepository {
  DiscuzForumTagDirectoryRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    DiscuzTagDirectoryHtmlParser? parser,
  }) : _config = config,
       _parser =
           parser ??
           DiscuzTagDirectoryHtmlParser(siteOrigin: config.siteOrigin);

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
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
    final tagId = query.tagId.trim();
    if (tagId.isEmpty || query.page < 1) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_tag_directory_query_invalid',
        diagnosticMessage: 'forum_tag_directory_query_invalid',
      );
    }
    final parameters = <String, String>{
      'mod': 'tag',
      'id': tagId,
      'type': 'thread',
      if (query.page > 1) 'page': '${query.page}',
    };
    final uri = _config.siteOrigin.replace(
      path: '/misc.php',
      queryParameters: parameters,
    );
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'tag.directory.html',
          pageKind: 'tag.directory',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.desktopHtml)
            .headers,
      ),
    );
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return DataReadFailure(
        kind: toReadFailureKind(failure.kind),
        code: failure.code,
        statusCode: failure.statusCode,
        diagnosticMessage: failure.code,
      );
    }
    try {
      final body = (result as ForumTransportSuccess<ForumResponse<Object?>>)
          .response
          .body;
      if (body is! String) throw const FormatException('text_expected');
      final data = _parser.parse(
        html: body,
        pageUrl: uri.toString(),
        expectedTagId: tagId,
        requestedPage: query.page,
      );
      return _validatedSuccess(query: query, data: data);
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_tag_directory_parse_failed',
        diagnosticMessage: 'forum_tag_directory_parse_failed',
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
        diagnosticMessage: 'forum_tag_directory_identity_mismatch',
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
          diagnosticMessage: 'forum_tag_directory_topic_identity_invalid',
        );
      }
    }
    final totalPages = data.pagination.totalPages;
    if (totalPages != null &&
        (totalPages < 1 || data.pagination.currentPage > totalPages)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_tag_directory_pagination_invalid',
        diagnosticMessage: 'forum_tag_directory_pagination_invalid',
      );
    }
    return DataReadSuccess(
      data: data,
      capabilities: _readCapabilitiesFor(data),
      metadata: const DataReadMetadata.network(),
    );
  }

  ForumTagDirectoryReadCapabilities _readCapabilitiesFor(
    ForumTagDirectoryData data,
  ) {
    final pagination = data.pagination;
    final directional =
        pagination.hasPrevious != null || pagination.hasNext != null;
    final topics = data.topics;
    DataCapabilitySupport optional(bool value) => value
        ? DataCapabilitySupport.supported
        : DataCapabilitySupport.unsupported;
    final values = _htmlCapabilities.values
        .withSupport(
          ForumTagDirectoryCapability.tagName,
          optional(data.tag.name?.trim().isNotEmpty == true),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicForum,
          optional(
            topics.any(
              (topic) =>
                  topic.forumId?.trim().isNotEmpty == true ||
                  topic.forumName?.trim().isNotEmpty == true,
            ),
          ),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicAuthor,
          optional(
            topics.any(
              (topic) =>
                  topic.authorId?.trim().isNotEmpty == true ||
                  topic.authorName?.trim().isNotEmpty == true,
            ),
          ),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicCreationTime,
          optional(topics.any((topic) => topic.createdAt != null)),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicReplyCount,
          optional(topics.any((topic) => topic.replyCount != null)),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicViewCount,
          optional(topics.any((topic) => topic.viewCount != null)),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicLastPost,
          optional(
            topics.any(
              (topic) =>
                  topic.lastPosterName != null || topic.lastPostAt != null,
            ),
          ),
        )
        .withSupport(
          ForumTagDirectoryCapability.topicAttachmentFlags,
          optional(
            topics.any(
              (topic) =>
                  topic.hasImageAttachment != null ||
                  topic.hasAttachment != null,
            ),
          ),
        )
        .withSupport(
          ForumTagDirectoryCapability.directionalPagination,
          optional(directional),
        )
        .withSupport(
          ForumTagDirectoryCapability.totalPageCount,
          optional(pagination.totalPages != null),
        );
    return ForumTagDirectoryReadCapabilities(
      values: values,
      paginationPrecision: pagination.totalPages != null
          ? PaginationPrecision.exact
          : directional
          ? PaginationPrecision.directional
          : PaginationPrecision.unknown,
    );
  }
}

final _htmlCapabilities = ForumTagDirectorySourceCapabilities(
  values: DataCapabilitySet.supported(ForumTagDirectoryCapability.values),
  paginationPrecision: PaginationPrecision.unknown,
);
