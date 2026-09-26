import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/current_account_summary_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

const _initialOwner = (uid: '42', revision: 0);
final _ownerProvider = StateProvider<VerifiedProfileOwner?>((ref) => null);

void main() {
  test(
    'first reader loads the verified account through networkFirst',
    () async {
      final repository = _Repository((_) async => _success('42'));
      final harness = _Harness(repository);
      expect(repository.policies, isEmpty);
      expect(
        harness.container.exists(currentAccountSummaryControllerProvider),
        isFalse,
      );

      harness.watch();
      expect(harness.state.isLoading, isTrue);
      expect(harness.state.data, isNull);
      await Future<void>.delayed(Duration.zero);

      expect(repository.policies, [CacheLoadPolicy.networkFirst]);
      expect(repository.userIds, ['42']);
      expect(harness.state.owner, _initialOwner);
      expect(harness.state.data?.identity.userId, '42');
      expect(harness.state.data?.creditTotal, 18);
      expect(harness.state.capabilities, same(_capabilities));
      expect(harness.state.failure, isNull);
      expect(harness.state.isLoading, isFalse);
    },
  );

  test(
    'anonymous owner does not request and verified login starts a read',
    () async {
      final repository = _Repository((_) async => _success('42'));
      final harness = _Harness(repository, owner: null)..watch();
      await harness.controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(repository.policies, isEmpty);
      expect(harness.state.owner, isNull);
      expect(harness.state.isLoading, isFalse);

      harness.setOwner(_initialOwner);
      expect(harness.state.data, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(repository.policies, hasLength(1));
      expect(harness.state.data?.identity.userId, '42');
    },
  );

  test('initial loading and concurrent refresh share one request', () async {
    final pending = Completer<_ReadResult>();
    final repository = _Repository((_) => pending.future);
    final harness = _Harness(repository)..watch();
    final first = harness.controller.refresh();
    final second = harness.controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(repository.policies, hasLength(1));
    expect(harness.state.isLoading, isTrue);

    pending.complete(_success('42'));
    await Future.wait([first, second]);
    expect(repository.policies, hasLength(1));
    expect(harness.state.data?.identity.userId, '42');
    expect(harness.state.isLoading, isFalse);
  });

  for (final nextOwner in <VerifiedProfileOwner>[
    (uid: '43', revision: 1),
    (uid: '42', revision: 1),
  ]) {
    test(
      'owner $nextOwner clears old data and ignores its late refresh',
      () async {
        final pending = Completer<_ReadResult>();
        final repository = _Repository((call) {
          if (call == 1) return pending.future;
          return Future.value(
            _success(call == 0 ? '42' : nextOwner.uid, creditTotal: call + 18),
          );
        });
        final harness = _Harness(repository)..watch();
        await Future<void>.delayed(Duration.zero);
        final oldRefresh = harness.controller.refresh();
        expect(harness.state.data?.creditTotal, 18);

        harness.setOwner(nextOwner);
        expect(harness.state.owner, nextOwner);
        expect(harness.state.data, isNull);
        expect(harness.state.capabilities, isNull);
        await Future<void>.delayed(Duration.zero);
        expect(harness.state.data?.identity.userId, nextOwner.uid);
        expect(harness.state.data?.creditTotal, 20);

        pending.complete(_success('42', creditTotal: 999));
        await oldRefresh;
        expect(harness.state.owner, nextOwner);
        expect(harness.state.data?.creditTotal, 20);
        expect(repository.policies, hasLength(3));
      },
    );
  }

  test(
    'logout hides content immediately and ignores the pending read',
    () async {
      final pending = Completer<_ReadResult>();
      final repository = _Repository(
        (call) => call == 0 ? Future.value(_success('42')) : pending.future,
      );
      final harness = _Harness(repository)..watch();
      await Future<void>.delayed(Duration.zero);
      final oldRefresh = harness.controller.refresh();
      harness.setOwner(null);
      expect(harness.state.owner, isNull);
      expect(harness.state.data, isNull);
      expect(harness.state.isLoading, isFalse);
      await harness.controller.refresh();

      pending.complete(_success('42'));
      await oldRefresh;
      expect(harness.state.data, isNull);
      expect(repository.policies, hasLength(2));
    },
  );

  for (final kind in <DataReadFailureKind>[
    DataReadFailureKind.network,
    DataReadFailureKind.timeout,
    DataReadFailureKind.unauthorized,
    DataReadFailureKind.parse,
  ]) {
    test(
      '$kind refresh retains data only for transient connection failures',
      () async {
        final repository = _Repository(
          (call) async => call == 0
              ? _success('42')
              : DataReadFailure(
                  kind: kind,
                  diagnosticMessage: 'synthetic_summary_failure',
                ),
        );
        final harness = _Harness(repository)..watch();
        await Future<void>.delayed(Duration.zero);
        final previous = harness.state;
        await harness.controller.refresh();

        final retain =
            kind == DataReadFailureKind.network ||
            kind == DataReadFailureKind.timeout;
        expect(harness.state.failure?.kind, kind);
        expect(harness.state.isLoading, isFalse);
        expect(harness.state.data, retain ? same(previous.data) : isNull);
        expect(
          harness.state.capabilities,
          retain ? same(previous.capabilities) : isNull,
        );
      },
    );
  }

  for (final invalidResponse in <({String name, _ReadResult result})>[
    (name: 'different UID', result: _success('43')),
    (
      name: 'cached response',
      result: _success(
        '42',
        metadata: const DataReadMetadata(
          origin: DataReadOrigin.cachedDocumentFallback,
          freshness: DataReadFreshness.current,
        ),
      ),
    ),
    (
      name: 'stale network response',
      result: _success(
        '42',
        metadata: const DataReadMetadata(
          origin: DataReadOrigin.network,
          freshness: DataReadFreshness.staleOrUnknown,
        ),
      ),
    ),
  ]) {
    test('${invalidResponse.name} clears the previous summary', () async {
      final repository = _Repository(
        (call) async => call == 0 ? _success('42') : invalidResponse.result,
      );
      final harness = _Harness(repository)..watch();
      await Future<void>.delayed(Duration.zero);
      await harness.controller.refresh();

      expect(harness.state.data, isNull);
      expect(harness.state.capabilities, isNull);
      expect(harness.state.failure?.kind, DataReadFailureKind.parse);
      expect(harness.state.isLoading, isFalse);
    });
  }

  test(
    'unexpected read failure is safe and manual refresh can recover',
    () async {
      final repository = _Repository((call) async {
        if (call == 0) throw StateError('synthetic transport failure');
        return _success('42');
      });
      final harness = _Harness(repository)..watch();
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.failure?.kind, DataReadFailureKind.unknown);
      expect(harness.state.data, isNull);
      expect(harness.state.isLoading, isFalse);

      await harness.controller.refresh();
      expect(harness.state.failure, isNull);
      expect(harness.state.data?.identity.userId, '42');
    },
  );

  test('a disposed reader cannot populate the next summary instance', () async {
    final pending = Completer<_ReadResult>();
    final repository = _Repository(
      (call) => call == 0
          ? pending.future
          : Future.value(_success('42', creditTotal: 21)),
    );
    final harness = _Harness(repository);
    final subscription = harness.watch();
    final oldRead = harness.controller.refresh();
    subscription.close();
    await harness.container.pump();
    expect(
      harness.container.exists(currentAccountSummaryControllerProvider),
      isFalse,
    );

    harness.watch();
    await Future<void>.delayed(Duration.zero);
    pending.complete(_success('42', creditTotal: 999));
    await oldRead;
    expect(harness.state.data?.creditTotal, 21);
    expect(repository.policies, hasLength(2));
  });
}

typedef _ReadResult =
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>;

final _capabilities = CurrentUserProfileReadCapabilities(
  values: DataCapabilitySet.supported(CurrentUserProfileCapability.values),
);

_ReadResult _success(
  String uid, {
  int creditTotal = 18,
  DataReadMetadata metadata = const DataReadMetadata.network(),
}) => DataReadSuccess(
  data: CurrentUserProfileData(
    identity: ProfileUserIdentity(userId: uid, displayName: 'sample-member'),
    creditTotal: creditTotal,
    groupId: '10',
    postCount: 24,
    threadCount: 6,
  ),
  capabilities: _capabilities,
  metadata: metadata,
);

final class _Harness {
  _Harness(
    _Repository repository, {
    VerifiedProfileOwner? owner = _initialOwner,
  }) {
    container = ProviderContainer(
      overrides: [
        _ownerProvider.overrideWith((ref) => owner),
        verifiedProfileOwnerProvider.overrideWith(
          (ref) => ref.watch(_ownerProvider),
        ),
        currentAccountSummaryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
  }

  late final ProviderContainer container;

  CurrentAccountSummaryState get state =>
      container.read(currentAccountSummaryControllerProvider);

  CurrentAccountSummaryController get controller =>
      container.read(currentAccountSummaryControllerProvider.notifier);

  ProviderSubscription<CurrentAccountSummaryState> watch() =>
      container.listen(currentAccountSummaryControllerProvider, (_, _) {});

  void setOwner(VerifiedProfileOwner? owner) {
    container.read(_ownerProvider.notifier).state = owner;
  }
}

final class _Repository implements CurrentAccountSummaryRepository {
  _Repository(this.onLoad);

  final Future<_ReadResult> Function(int call) onLoad;
  final List<CacheLoadPolicy> policies = [];
  final List<String> userIds = [];

  @override
  CurrentUserProfileSourceCapabilities get capabilities =>
      CurrentUserProfileSourceCapabilities(values: _capabilities.values);

  @override
  Future<_ReadResult> load(
    CurrentAccountSummaryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    final call = policies.length;
    userIds.add(query.userId);
    policies.add(cachePolicy);
    return onLoad(call);
  }
}
