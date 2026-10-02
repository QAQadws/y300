// ignore_for_file: public_member_api_docs

import '../client/forum_client_config.dart';
import '../cache/forum_cache.dart';
import 'account_summary_snapshot_codec.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_account_summary_parser.dart';
import 'discuz_profile_html_parsers.dart';

final class DiscuzCurrentAccountSummaryRepository
    implements
        CurrentAccountSummaryRepository,
        CurrentAccountSummaryCacheReader {
  DiscuzCurrentAccountSummaryRepository({
    required this.config,
    required this.network,
    required this.requestProfiles,
    this.snapshotStore,
  }) : _parser = DiscuzAccountSummaryParser(siteOrigin: config.siteOrigin);

  final ForumClientConfig config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final DiscuzAccountSummaryParser _parser;
  final ForumSnapshotStore? snapshotStore;
  static const _codec = AccountSummarySnapshotCodec();
  final Map<String, int> _readGenerations = {};
  final Map<String, Future<void>> _snapshotWrites = {};

  Future<void> _saveSnapshot(
    String uid,
    int generation,
    AccountSummarySnapshot value,
  ) async {
    final write = (_snapshotWrites[uid] ?? Future<void>.value()).then((
      _,
    ) async {
      if (_readGenerations[uid] != generation) return;
      try {
        await snapshotStore?.put(
          _descriptor(uid),
          value,
          _codec,
          policy: const ForumSnapshotPolicy(
            freshFor: Duration.zero,
            keepStaleFor: Duration.zero,
            retainLongTerm: true,
          ),
        );
      } on Object {
        // Cache failure never discards a validated network result.
      }
    });
    _snapshotWrites[uid] = write;
    await write;
    if (identical(_snapshotWrites[uid], write)) _snapshotWrites.remove(uid);
  }

  ForumSnapshotDescriptor _descriptor(String uid) => ForumSnapshotDescriptor(
    cacheKey: '${config.siteOrigin.origin}:account.summary:$uid',
    ownerType: 'profile',
    ownerId: uid,
    snapshotType: _codec.snapshotType,
  );

  @override
  Future<AccountSummarySnapshot?> readCached(
    CurrentAccountSummaryQuery query,
  ) async {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(query.userId)) return null;
    try {
      final cached = await snapshotStore?.get(
        _descriptor(query.userId),
        _codec,
      );
      if (cached?.value.data.identity.userId != query.userId) return null;
      if (cached == null) return null;
      return DataReadSuccess(
        data: cached.value.data,
        capabilities: cached.value.capabilities,
        metadata: const DataReadMetadata(
          origin: DataReadOrigin.freshSnapshot,
          freshness: DataReadFreshness.staleOrUnknown,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  CurrentUserProfileSourceCapabilities get capabilities =>
      CurrentUserProfileSourceCapabilities(
        values: DataCapabilitySet.supported(
          CurrentUserProfileCapability.values.where(
            (value) => value != CurrentUserProfileCapability.postCount,
          ),
        ),
      );

  @override
  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load(
    CurrentAccountSummaryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final uid = query.userId;
    if (!RegExp(r'^[1-9]\d*$').hasMatch(uid)) {
      return _failure(
        DataReadFailureKind.business,
        'account_summary_query_invalid',
      );
    }
    final uri = config.siteOrigin.replace(
      path: '/home.php',
      queryParameters: {'mod': 'space', 'uid': uid, 'do': 'profile'},
    );
    final generation = (_readGenerations[uid] ?? 0) + 1;
    _readGenerations[uid] = generation;
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'profile.account.summary.desktop',
          module: 'profile',
          pageKind: 'profile.account.summary',
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
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    final body = response.body;
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        (body is String && DiscuzProfileAuthPageDetector.isLoginPage(body))) {
      return _failure(
        DataReadFailureKind.unauthorized,
        'account_summary_unauthorized',
      );
    }
    if (response.statusCode != 200 || body is! String) {
      return _failure(
        DataReadFailureKind.parse,
        'account_summary_response_invalid',
      );
    }
    try {
      if (!_parser.isExpectedUri(response.uri, uid)) {
        return _failure(
          DataReadFailureKind.parse,
          'account_summary_identity_invalid',
        );
      }
      final data = _parser.parse(body, uid);
      final present = <CurrentUserProfileCapability>[
        CurrentUserProfileCapability.stableUserIdentity,
        CurrentUserProfileCapability.userName,
        if (data.avatarUrl != null)
          CurrentUserProfileCapability.avatarReference,
        if (data.groupId != null) CurrentUserProfileCapability.groupIdentity,
        if (data.groupName != null) CurrentUserProfileCapability.groupName,
        if (data.creditTotal != null) CurrentUserProfileCapability.creditTotal,
        if (data.threadCount != null) CurrentUserProfileCapability.threadCount,
        if (data.replyCount != null) CurrentUserProfileCapability.replyCount,
      ];
      final value = DataReadSuccess(
        data: data,
        capabilities: CurrentUserProfileReadCapabilities(
          values: DataCapabilitySet.supported(present),
        ),
        metadata: const DataReadMetadata.network(),
      );
      await _saveSnapshot(uid, generation, value);
      return value;
    } on ForumUserProfileUnauthorized {
      return _failure(
        DataReadFailureKind.unauthorized,
        'account_summary_unauthorized',
      );
    } on FormatException catch (error) {
      if (const {
        'account_session_identity_invalid',
        'account_session_identity_mismatch',
        'account_profile_identity_mismatch',
      }.contains(error.message)) {
        return _failure(
          DataReadFailureKind.parse,
          'account_summary_identity_invalid',
        );
      }
      return _failure(
        DataReadFailureKind.parse,
        'account_summary_parse_failed',
      );
    }
  }

  DataReadFailure<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  _failure(DataReadFailureKind kind, String code) =>
      DataReadFailure(kind: kind, code: code, diagnosticMessage: code);
}
