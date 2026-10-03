// ignore_for_file: public_member_api_docs

import 'package:html/parser.dart' as html;

import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/user_thread_directory.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_profile_html_parsers.dart';
import 'discuz_user_thread_directory_parser.dart';

/// Network-only user-directory reads on the shared Host transport and session.
final class DiscuzUserThreadDirectoryRepository
    implements UserThreadDirectoryRepository {
  DiscuzUserThreadDirectoryRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
  }) : _config = config,
       _parser = DiscuzUserThreadDirectoryParser(siteOrigin: config.siteOrigin);

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final DiscuzUserThreadDirectoryParser _parser;

  @override
  UserThreadDirectorySourceCapabilities get capabilities =>
      UserThreadDirectorySourceCapabilities(
        values: DataCapabilitySet.from(
          supported: UserThreadDirectoryCapability.values.where(
            (c) => c != UserThreadDirectoryCapability.totalPageCount,
          ),
          unsupported: const [UserThreadDirectoryCapability.totalPageCount],
        ),
      );

  @override
  Future<
    DataReadResult<UserThreadDirectoryData, UserThreadDirectoryReadCapabilities>
  >
  load(
    UserThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return _failure(
        DataReadFailureKind.cancelled,
        'user_thread_directory_cancelled',
      );
    }
    if (!RegExp(r'^[1-9]\d*$').hasMatch(query.userId) ||
        (query.viewerUserId != null &&
            !RegExp(r'^[1-9]\d*$').hasMatch(query.viewerUserId!)) ||
        query.page < 1) {
      return _failure(
        DataReadFailureKind.business,
        'user_thread_directory_query_invalid',
      );
    }
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: _config.siteOrigin.replace(
          path: '/home.php',
          queryParameters: {
            'mod': 'space',
            'uid': query.userId,
            'do': 'thread',
            'view': 'me',
            'type': query.type == UserThreadDirectoryType.replies
                ? 'reply'
                : 'thread',
            'page': '${query.page}',
            'mobile': '2',
          },
        ),
        cancellation: cancellation,
        context: ForumRequestContext(
          operation: 'profile.thread.directory.html',
          module: 'profile',
          pageKind: 'profile.thread.${query.type.name}',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.mobileHtml)
            .headers,
      ),
    );
    if (cancellation?.isCancelled ?? false) {
      return _failure(
        DataReadFailureKind.cancelled,
        'user_thread_directory_cancelled',
      );
    }
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _failure(toReadFailureKind(failure.kind), failure.code);
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    final source = response.body;
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        (response.uri.path == '/member.php' &&
            response.uri.queryParameters['mod'] == 'logging')) {
      return _failure(
        DataReadFailureKind.unauthorized,
        'user_thread_directory_login_required',
      );
    }
    if (source is! String || source.trim().isEmpty) {
      return _failure(
        DataReadFailureKind.parse,
        'user_thread_directory_body_invalid',
      );
    }
    if (DiscuzProfileAuthPageDetector.isLoginPage(source)) {
      return _failure(
        DataReadFailureKind.unauthorized,
        'user_thread_directory_login_required',
      );
    }
    if (response.statusCode != 200) {
      return _failure(
        DataReadFailureKind.server,
        'user_thread_directory_http_failed',
      );
    }
    final document = html.parse(source);
    if (document.querySelector('#messagetext, .jump_c, .alert_error') != null ||
        (document.querySelector('#ct .nfl .f_c table .avt') != null &&
            document.querySelector('#ct a[href*="do=friend"]') != null)) {
      return _failure(
        DataReadFailureKind.business,
        'user_thread_directory_unavailable',
      );
    }
    try {
      if (!_parser.isExpectedResponseUri(response.uri, query)) {
        return _failure(
          DataReadFailureKind.parse,
          'user_thread_directory_context_invalid',
        );
      }
      final data = _parser.parse(source: source, query: query);
      return DataReadSuccess(
        data: data,
        capabilities: _readCapabilities(data),
        metadata: const DataReadMetadata.network(),
      );
    } on UserThreadDirectoryUnauthorized {
      return _failure(
        DataReadFailureKind.unauthorized,
        'user_thread_directory_login_required',
      );
    } on FormatException {
      return _failure(
        DataReadFailureKind.parse,
        'user_thread_directory_parse_failed',
      );
    }
  }

  UserThreadDirectoryReadCapabilities _readCapabilities(
    UserThreadDirectoryData data,
  ) {
    var values = capabilities.values;
    final optional = {
      UserThreadDirectoryCapability.author: data.items.any(
        (i) => i.authorName != null,
      ),
      UserThreadDirectoryCapability.excerpt: data.items.any(
        (i) => i.excerpt != null,
      ),
      UserThreadDirectoryCapability.publishedAtText: data.items.any(
        (i) => i.publishedAtText != null,
      ),
      UserThreadDirectoryCapability.forum: data.items.any(
        (i) => i.forumId != null,
      ),
      UserThreadDirectoryCapability.statistics: data.items.any(
        (i) => i.views != null || i.replies != null,
      ),
      UserThreadDirectoryCapability.images: data.items.any(
        (i) => i.images.isNotEmpty,
      ),
      UserThreadDirectoryCapability.replyPreviews: data.items.any(
        (i) => i.replyPreviews.isNotEmpty,
      ),
      UserThreadDirectoryCapability.badges: data.items.any(
        (i) => i.badges.isNotEmpty,
      ),
    };
    for (final entry in optional.entries) {
      if (!entry.value) {
        values = values.withSupport(entry.key, DataCapabilitySupport.unknown);
      }
    }
    return UserThreadDirectoryReadCapabilities(values: values);
  }

  DataReadFailure<UserThreadDirectoryData, UserThreadDirectoryReadCapabilities>
  _failure(DataReadFailureKind kind, String code) =>
      DataReadFailure(kind: kind, code: code, diagnosticMessage: code);
}
