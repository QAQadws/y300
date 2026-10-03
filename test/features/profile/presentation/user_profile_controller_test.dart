import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/user_profile_controller.dart';

const _owner = (uid: '42', revision: 0);
final _ownerProvider = StateProvider<VerifiedProfileOwner?>((ref) => null);

void main() {
  test(
    'public refresh is single-flight and preserves content offline',
    () async {
      final pending = Completer<_Read>();
      final repository = _Repository(
        (query, call) =>
            call == 0 ? Future.value(_success(query.userId)) : pending.future,
      );
      final harness = _Harness(repository);
      await harness.loaded;
      final first = harness.refresh();
      final second = harness.refresh();
      expect(repository.queries, hasLength(2));
      expect(harness.state.isRefreshing, isTrue);
      pending.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.network,
          diagnosticMessage: 'offline',
        ),
      );
      await Future.wait([first, second]);
      expect(harness.state.data?.identity.userId, '7');
      expect(harness.state.isRefreshing, isFalse);
      expect(harness.state.failure?.kind, DataReadFailureKind.network);
      expect(repository.policies, [
        CacheLoadPolicy.cacheFirst,
        CacheLoadPolicy.networkFirst,
      ]);
    },
  );

  test('changing the viewer cancels and rejects the old public read', () async {
    final pending = Completer<_Read>();
    final repository = _Repository(
      (query, call) => call == 1
          ? pending.future
          : Future.value(_success(query.userId, viewer: query.viewerUserId)),
    );
    final harness = _Harness(repository, owner: _owner);
    await harness.loaded;
    final oldRefresh = harness.refresh();
    final oldCancellation = repository.cancellations[1]!;
    harness.setOwner((uid: '43', revision: 1));
    await _flush();
    expect(oldCancellation.isCancelled, isTrue);
    await harness.loaded;
    expect(harness.state.ownerUid, '43');
    pending.complete(_success('7', viewer: '42', name: 'old-viewer-result'));
    await oldRefresh;
    expect(harness.state.ownerUid, '43');
    expect(harness.state.data?.identity.displayName, 'current-result');
    expect(repository.queries.last.viewerUserId, '43');
  });

  test('same UID with a new revision owns a new public read', () async {
    final repository = _Repository(
      (query, _) => Future.value(_success(query.userId)),
    );
    final harness = _Harness(repository, owner: _owner);
    await harness.loaded;
    final oldState = harness.state;
    harness.setOwner((uid: '42', revision: 1));
    await _flush();
    await harness.loaded;
    expect(oldState.belongsToSession((uid: '42', revision: 1)), isFalse);
    expect(harness.state.ownerRevision, 1);
    expect(repository.queries, hasLength(2));
  });

  test('disposing a public route cancels its request', () async {
    final pending = Completer<_Read>();
    final repository = _Repository((_, _) => pending.future);
    final harness = _Harness(repository);
    await _flush();
    final cancellation = repository.cancellations.single!;
    harness.dispose();
    expect(cancellation.isCancelled, isTrue);
    pending.complete(_success('7'));
    await _flush();
  });

  test('public profile rejects another target or another viewer', () async {
    for (final result in [_success('8'), _success('7', viewer: '99')]) {
      final harness = _Harness(
        _Repository((_, _) => Future.value(result)),
        owner: _owner,
      );
      await harness.loaded;
      expect(harness.state.data, isNull);
      expect(harness.state.failure?.kind, DataReadFailureKind.parse);
    }
  });

  test('public route for the viewer uses verified self provenance', () async {
    final repository = _Repository(
      (query, _) => Future.value(_success(query.userId, metadata: _cached)),
    );
    final harness = _Harness(repository, target: '42', owner: _owner);
    await harness.loaded;
    expect(repository.queries.single.view, ForumUserProfileView.self);
    expect(repository.policies.single, CacheLoadPolicy.networkFirst);
    expect(harness.state.data, isNull);
    expect(harness.state.failure?.kind, DataReadFailureKind.parse);
  });

  test('self controller does not read without a verified owner', () async {
    final repository = _Repository(
      (query, _) => Future.value(_success(query.userId)),
    );
    final harness = _Harness(repository, self: true);
    await harness.loaded;
    await harness.refresh();
    expect(repository.queries, isEmpty);
    expect(harness.state.data, isNull);
  });

  test(
    'self controller cancels logout and ignores its late response',
    () async {
      final pending = Completer<_Read>();
      final repository = _Repository(
        (query, call) =>
            call == 0 ? Future.value(_success(query.userId)) : pending.future,
      );
      final harness = _Harness(repository, self: true, owner: _owner);
      await harness.loaded;
      final oldRefresh = harness.refresh();
      harness.setOwner(null);
      await _flush();
      await harness.loaded;
      expect(repository.cancellations.last!.isCancelled, isTrue);
      pending.complete(_success('42'));
      await oldRefresh;
      expect(harness.state.data, isNull);
      expect(harness.state.ownerUid, isNull);
    },
  );

  test('access rejection clears a previously loaded public profile', () async {
    final harness = _Harness(
      _Repository(
        (query, call) => Future.value(
          call == 0
              ? _success(query.userId)
              : const DataReadFailure(
                  kind: DataReadFailureKind.unauthorized,
                  diagnosticMessage: 'session_expired',
                ),
        ),
      ),
    );
    await harness.loaded;
    await harness.refresh();
    expect(harness.state.data, isNull);
    expect(harness.state.capabilities, isNull);
    expect(harness.state.failure?.kind, DataReadFailureKind.unauthorized);
  });

  test('unexpected read exceptions become retryable typed failures', () async {
    final repository = _Repository((query, call) {
      if (call == 0) throw StateError('fixture exception');
      return Future.value(_success(query.userId));
    });
    final harness = _Harness(repository);
    await harness.loaded;
    expect(harness.state.failure?.kind, DataReadFailureKind.unknown);
    await harness.refresh();
    expect(harness.state.data?.identity.userId, '7');
    expect(harness.state.failure, isNull);
  });

  test('invalid UID never reaches the repository', () async {
    final repository = _Repository((_, _) => Future.value(_success('7')));
    final harness = _Harness(repository, target: '0');
    await harness.loaded;
    expect(repository.queries, isEmpty);
    expect(harness.state.failure?.kind, DataReadFailureKind.parse);
  });
}

typedef _Read =
    DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>;

const _cached = DataReadMetadata(
  origin: DataReadOrigin.freshSnapshot,
  freshness: DataReadFreshness.freshCache,
);

_Read _success(
  String uid, {
  String? viewer,
  String name = 'current-result',
  DataReadMetadata metadata = const DataReadMetadata.network(),
}) => DataReadSuccess(
  data: ForumUserProfileData(
    identity: ProfileUserIdentity(userId: uid, displayName: name),
    viewerUserId: viewer,
    metrics: const [],
    details: const [],
  ),
  capabilities: ForumUserProfileReadCapabilities(
    values: DataCapabilitySet.supported(ForumUserProfileCapability.values),
  ),
  metadata: metadata,
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _Harness {
  _Harness(
    _Repository repository, {
    this.target = '7',
    this.self = false,
    VerifiedProfileOwner? owner,
  }) {
    container = ProviderContainer(
      overrides: [
        _ownerProvider.overrideWith((ref) => owner),
        verifiedProfileOwnerProvider.overrideWith(
          (ref) => ref.watch(_ownerProvider),
        ),
        forumUserProfileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    container.listen(
      self ? myUserProfileProvider : userProfileProvider(target),
      (_, _) {},
    );
    addTearDown(dispose);
  }

  final String target;
  final bool self;
  late final ProviderContainer container;
  bool _disposed = false;

  ForumUserProfilePageState get state => container
      .read(self ? myUserProfileProvider : userProfileProvider(target))
      .asData!
      .value;
  Future<ForumUserProfilePageState> get loaded => container.read(
    self ? myUserProfileProvider.future : userProfileProvider(target).future,
  );
  Future<void> refresh() => self
      ? container.read(myUserProfileProvider.notifier).refresh()
      : container.read(userProfileProvider(target).notifier).refresh();

  void setOwner(VerifiedProfileOwner? owner) =>
      container.read(_ownerProvider.notifier).state = owner;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }
}

final class _Repository implements ForumUserProfileRepository {
  _Repository(this.onLoad);
  final Future<_Read> Function(ForumUserProfileQuery query, int call) onLoad;
  final queries = <ForumUserProfileQuery>[];
  final policies = <CacheLoadPolicy>[];
  final cancellations = <ForumRequestCancellation?>[];

  @override
  final capabilities = ForumUserProfileSourceCapabilities(
    values: DataCapabilitySet.supported(ForumUserProfileCapability.values),
  );

  @override
  Future<_Read> load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) {
    final call = queries.length;
    queries.add(query);
    policies.add(cachePolicy);
    cancellations.add(cancellation);
    return onLoad(query, call);
  }
}
