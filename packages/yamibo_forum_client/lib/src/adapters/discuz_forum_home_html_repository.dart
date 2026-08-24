import '../cache/forum_cache.dart';
import '../cache/forum_cache_key_canonicalizer.dart';
import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_directory.dart';
import '../contracts/forum_home.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_session_store.dart';
import 'forum_home_html_parser.dart';
import 'forum_home_snapshot_codec.dart';

final class DiscuzForumHomeHtmlRepository
    implements ForumHomeRepository, ForumDirectoryRepository {
  DiscuzForumHomeHtmlRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    this.sessionStore,
    this.documentStore,
    this.snapshotStore,
    ForumHomeHtmlParser? parser,
    ForumCacheKeyCanonicalizer? cacheKeys,
    this.snapshotCodec = const ForumHomeSnapshotCodec(),
    this.snapshotPolicy = const ForumSnapshotPolicy(
      freshFor: Duration(minutes: 5),
      keepStaleFor: Duration(days: 1),
    ),
    DateTime Function()? now,
  }) : _config = config,
       _parser = parser ?? ForumHomeHtmlParser(siteOrigin: config.siteOrigin),
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
  final ForumHomeHtmlParser _parser;
  final ForumCacheKeyCanonicalizer _cacheKeys;
  final ForumHomeSnapshotCodec snapshotCodec;
  final ForumSnapshotPolicy snapshotPolicy;
  final DateTime Function() _now;

  @override
  ForumHomeSourceCapabilities get homeCapabilities => _homeCapabilities;

  @override
  ForumDirectorySourceCapabilities get capabilities => _directoryCapabilities;

  ForumDocumentRequestProfile _profile(ForumHomeQuery query) =>
      switch (query.audience) {
        ForumHomeAudience.anonymous => ForumDocumentRequestProfile.anonymous,
        ForumHomeAudience.authenticated => ForumDocumentRequestProfile.loggedIn,
        ForumHomeAudience.automatic =>
          sessionStore?.readCurrent()?.isLoggedIn == true
              ? ForumDocumentRequestProfile.loggedIn
              : ForumDocumentRequestProfile.anonymous,
      };

  @override
  Future<ForumHomeCachedRead?> readCached(ForumHomeQuery query) async {
    final profile = _profile(query);
    final snapshotDescriptor = _cacheKeys.forumHomeSnapshot(
      requestProfile: profile,
    );
    try {
      final cached = await snapshotStore?.get(
        snapshotDescriptor,
        snapshotCodec,
      );
      if (cached != null && _valid(cached.value)) {
        return ForumHomeCachedRead(
          data: cached.value,
          capabilities: homeCapabilities.toReadCapabilities(),
          metadata: DataReadMetadata(
            origin: DataReadOrigin.freshSnapshot,
            freshness: cached.isFresh(_now())
                ? DataReadFreshness.freshCache
                : DataReadFreshness.staleOrUnknown,
          ),
          updatedAt: cached.updatedAt,
        );
      }
    } catch (_) {}
    final documentDescriptor = _cacheKeys.forumHome(requestProfile: profile);
    try {
      final document = await documentStore?.get(documentDescriptor);
      if (document == null) return null;
      final data = _parser.parse(document.body);
      if (!_valid(data)) return null;
      await documentStore?.touch(documentDescriptor, _now());
      return ForumHomeCachedRead(
        data: data,
        capabilities: homeCapabilities.toReadCapabilities(),
        metadata: const DataReadMetadata(
          origin: DataReadOrigin.cachedDocumentFallback,
          freshness: DataReadFreshness.staleOrUnknown,
        ),
        updatedAt: document.updatedAt,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DataReadResult<ForumHomeDocument, ForumHomeReadCapabilities>> loadHome(
    ForumHomeQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final profile = _profile(query);
    if (cachePolicy == CacheLoadPolicy.cacheFirst) {
      final cached = await readCached(query);
      if (cached != null &&
          cached.metadata.freshness == DataReadFreshness.freshCache) {
        return DataReadSuccess(
          data: cached.data,
          capabilities: cached.capabilities,
          metadata: cached.metadata,
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
          operation: 'forum.home.html',
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
      final cached = await readCached(query);
      if (cached != null) {
        return DataReadSuccess(
          data: cached.data,
          capabilities: cached.capabilities,
          metadata: const DataReadMetadata(
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
      if (response.body is! String) {
        throw const FormatException('forum_home_text_expected');
      }
      final data = _parser.parse(response.body as String);
      if (!_valid(data)) {
        throw const FormatException('forum_home_identity_invalid');
      }
      await _persist(profile, response, data);
      return DataReadSuccess(
        data: data,
        capabilities: homeCapabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_home_parse_failed',
        diagnosticMessage: error.message,
      );
    }
  }

  @override
  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  load(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final result = await loadHome(
      const ForumHomeQuery(),
      cachePolicy: cachePolicy,
    );
    return result.when(
      success: (data, _, metadata) => DataReadSuccess(
        data: data.directory,
        capabilities: capabilities.toReadCapabilities(),
        metadata: metadata,
      ),
      failure: (failure) => failure.retype(),
    );
  }

  Future<void> _persist(
    ForumDocumentRequestProfile profile,
    ForumResponse<Object?> response,
    ForumHomeDocument data,
  ) async {
    final document = _cacheKeys.forumHome(requestProfile: profile);
    final now = _now();
    try {
      await documentStore?.put(
        ForumCachedDocument(
          descriptor: document,
          body: response.body as String,
          contentType: response.headers['content-type']?.firstOrNull,
          statusCode: response.statusCode,
          fetchedAt: now,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );
    } catch (_) {}
    try {
      await snapshotStore?.put(
        _cacheKeys.forumHomeSnapshot(requestProfile: profile),
        data,
        snapshotCodec,
        policy: snapshotPolicy,
      );
    } catch (_) {}
  }

  bool _valid(ForumHomeDocument data) {
    final sections = <String>{};
    final forums = <String>{};
    final favorites = <String>{};
    return data.directory.sections.every(
          (section) =>
              section.identity.trim().isNotEmpty &&
              sections.add(section.identity) &&
              section.forums.every(
                (forum) => forum.fid.trim().isNotEmpty && forums.add(forum.fid),
              ),
        ) &&
        data.favoriteForums.every(
          (forum) => forum.fid.trim().isNotEmpty && favorites.add(forum.fid),
        );
  }
}

final _homeCapabilities = ForumHomeSourceCapabilities(
  values: DataCapabilitySet.supported(ForumHomeCapability.values),
);

final _directoryCapabilities = ForumDirectorySourceCapabilities(
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
