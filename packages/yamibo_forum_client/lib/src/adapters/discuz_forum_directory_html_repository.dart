import '../cache/forum_cache.dart';
import '../cache/forum_cache_key_canonicalizer.dart';
import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_directory.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_session_store.dart';
import 'forum_directory_html_parser.dart';
import 'forum_directory_snapshot_codec.dart';

final class DiscuzForumDirectoryHtmlRepository
    implements ForumDirectoryRepository {
  DiscuzForumDirectoryHtmlRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    this.sessionStore,
    this.documentStore,
    this.snapshotStore,
    ForumDirectoryHtmlParser? parser,
    ForumCacheKeyCanonicalizer? cacheKeys,
    this.snapshotCodec = const ForumDirectorySnapshotCodec(),
    DateTime Function()? now,
  }) : _config = config,
       _parser =
           parser ?? ForumDirectoryHtmlParser(siteOrigin: config.siteOrigin),
       _cacheKeys =
           cacheKeys ??
           ForumCacheKeyCanonicalizer(siteOrigin: config.siteOrigin),
       _now = now ?? DateTime.now;

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final ForumSessionStore? sessionStore;
  final ForumDocumentStore? documentStore;
  final ForumSnapshotStore? snapshotStore;
  final ForumDirectoryHtmlParser _parser;
  final ForumCacheKeyCanonicalizer _cacheKeys;
  final ForumDirectorySnapshotCodec snapshotCodec;
  final DateTime Function() _now;

  @override
  ForumDirectorySourceCapabilities get capabilities => _htmlCapabilities;

  @override
  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  load(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final profile = sessionStore?.readCurrent()?.isLoggedIn == true
        ? ForumDocumentRequestProfile.loggedIn
        : ForumDocumentRequestProfile.anonymous;
    final document = _cacheKeys.forumHome(requestProfile: profile);
    final snapshot = _cacheKeys.forumHomeSnapshot(requestProfile: profile);
    if (cachePolicy == CacheLoadPolicy.cacheFirst) {
      final cached = await _snapshot(snapshot);
      if (cached != null && cached.isFresh(_now())) {
        return _success(
          cached.value,
          const DataReadMetadata(
            origin: DataReadOrigin.freshSnapshot,
            freshness: DataReadFreshness.freshCache,
          ),
        );
      }
    }

    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: _config.siteOrigin.replace(
          path: '/index.php',
          queryParameters: const {'mobile': '2'},
        ),
        context: const ForumRequestContext(
          operation: 'forum.directory.html',
          pageKind: 'forum.home',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.mobileHtml)
            .headers,
      ),
    );
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      final fallback = await _document(document);
      if (fallback != null) {
        return _success(
          fallback,
          const DataReadMetadata(
            origin: DataReadOrigin.cachedDocumentFallback,
            freshness: DataReadFreshness.staleOrUnknown,
          ),
        );
      }
      return DataReadFailure(
        kind: toReadFailureKind(failure.kind),
        code: failure.code,
        statusCode: failure.statusCode,
        diagnosticMessage: failure.code,
      );
    }
    try {
      final response =
          (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
      final body = response.body;
      if (body is! String) throw const FormatException('text_expected');
      final data = _parser.parse(body);
      await _putDocument(document, body, response);
      return _success(data, const DataReadMetadata.network());
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_directory_parse_failed',
        diagnosticMessage: 'forum_directory_parse_failed',
      );
    }
  }

  DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities> _success(
    ForumDirectoryData data,
    DataReadMetadata metadata,
  ) {
    if (!_valid(data)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_directory_identity_invalid',
        diagnosticMessage: 'forum_directory_identity_invalid',
      );
    }
    return DataReadSuccess(
      data: data,
      capabilities: capabilities.toReadCapabilities(),
      metadata: metadata,
    );
  }

  Future<ForumCachedSnapshot<ForumDirectoryData>?> _snapshot(
    ForumSnapshotDescriptor descriptor,
  ) async {
    try {
      return await snapshotStore?.get(descriptor, snapshotCodec);
    } catch (_) {
      return null;
    }
  }

  Future<ForumDirectoryData?> _document(
    ForumDocumentDescriptor descriptor,
  ) async {
    try {
      final value = await documentStore?.get(descriptor);
      if (value == null) return null;
      final data = _parser.parse(value.body);
      await documentStore?.touch(descriptor, _now());
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _putDocument(
    ForumDocumentDescriptor descriptor,
    String body,
    ForumResponse<Object?> response,
  ) async {
    try {
      final now = _now();
      await documentStore?.put(
        ForumCachedDocument(
          descriptor: descriptor,
          body: body,
          contentType: response.headers['content-type']?.firstOrNull,
          statusCode: response.statusCode,
          fetchedAt: now,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );
    } catch (_) {
      return;
    }
  }

  bool _valid(ForumDirectoryData data) {
    final sections = <String>{};
    final forums = <String>{};
    return data.sections.every(
      (section) =>
          section.identity.trim().isNotEmpty &&
          sections.add(section.identity) &&
          section.forums.every(
            (forum) => forum.fid.trim().isNotEmpty && forums.add(forum.fid),
          ),
    );
  }
}

final _htmlCapabilities = ForumDirectorySourceCapabilities(
  values: DataCapabilitySet<ForumDirectoryCapability>.from(
    supported: const [
      ForumDirectoryCapability.stableSectionIdentity,
      ForumDirectoryCapability.orderedSections,
      ForumDirectoryCapability.stableForumIdentity,
      ForumDirectoryCapability.orderedForums,
      ForumDirectoryCapability.forumDescription,
      ForumDirectoryCapability.todayPostCount,
    ],
    unsupported: const [ForumDirectoryCapability.nestedForums],
  ),
);
