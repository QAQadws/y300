import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/account_display_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

final class CurrentAccountSummaryState {
  const CurrentAccountSummaryState({
    this.owner,
    this.previewUid,
    this.data,
    this.capabilities,
    this.failure,
    this.isLoading = false,
    this.networkRevision = 0,
  });

  final VerifiedProfileOwner? owner;
  final String? previewUid;
  String? get displayUid => owner?.uid ?? previewUid;
  final CurrentUserProfileData? data;
  final CurrentUserProfileReadCapabilities? capabilities;
  final DataReadFailure<
    CurrentUserProfileData,
    CurrentUserProfileReadCapabilities
  >?
  failure;
  final bool isLoading;

  /// Changes only after a validated network read, triggering avatar revalidation.
  final int networkRevision;
}

final currentAccountSummaryControllerProvider =
    NotifierProvider.autoDispose<
      CurrentAccountSummaryController,
      CurrentAccountSummaryState
    >(CurrentAccountSummaryController.new);

/// Publishes local display data first; only verified owners may refresh remotely.
final class CurrentAccountSummaryController
    extends Notifier<CurrentAccountSummaryState> {
  int _generation = 0;
  int _networkRevision = 0;
  Future<void>? _readFlight;
  CurrentAccountSummaryState _last = const CurrentAccountSummaryState();
  VerifiedProfileOwner? _identityBlockedOwner;
  VerifiedProfileOwner? _lastLoadedOwner;

  @override
  CurrentAccountSummaryState build() {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final previewUid =
        owner?.uid ?? ref.watch(accountDisplayControllerProvider);
    final uid = owner?.uid ?? previewUid;
    final generation = ++_generation;
    _readFlight = null;
    ref.onDispose(() => _generation++);
    final previous = _last.displayUid == uid ? _last : null;
    final blocked = owner != null && owner == _identityBlockedOwner;
    _last = CurrentAccountSummaryState(
      owner: owner,
      previewUid: previewUid,
      data: blocked ? null : previous?.data,
      capabilities: blocked ? null : previous?.capabilities,
      failure: blocked ? previous?.failure : null,
      networkRevision: previous?.networkRevision ?? 0,
    );
    if (uid != null && !blocked) {
      unawaited(Future<void>.microtask(() => _restore(uid, owner, generation)));
    }
    return _last;
  }

  void _publish(CurrentAccountSummaryState value) {
    _last = value;
    state = value;
  }

  Future<void> _restore(
    String uid,
    VerifiedProfileOwner? owner,
    int generation,
  ) async {
    if (!_isCurrent(uid, generation)) return;
    if (state.data == null) {
      try {
        final repository = ref.read(currentAccountSummaryRepositoryProvider);
        if (repository is CurrentAccountSummaryCacheReader) {
          final cached = await (repository as CurrentAccountSummaryCacheReader)
              .readCached(CurrentAccountSummaryQuery(userId: uid));
          if (!_isCurrent(uid, generation) ||
              (owner != null && _identityBlockedOwner == owner)) {
            return;
          }
          if (cached != null &&
              cached.data.identity.userId == uid &&
              state.data == null) {
            _publish(
              CurrentAccountSummaryState(
                owner: owner,
                previewUid: uid,
                data: cached.data,
                capabilities: cached.capabilities,
                isLoading: state.isLoading,
                failure: state.failure,
                networkRevision: state.networkRevision,
              ),
            );
          }
        }
      } on Object {
        // Corrupt or unavailable cache does not block the fresh read.
      }
    }
    if (_isCurrent(uid, generation) &&
        owner != null &&
        (state.networkRevision == 0 || _lastLoadedOwner != owner) &&
        !state.isLoading &&
        state.failure == null) {
      await refresh();
    }
  }

  Future<void> refresh() {
    final owner = state.owner;
    if (owner == null) return Future.value();
    if (_readFlight case final pending?) return pending;
    _identityBlockedOwner = null;
    final future = _load(owner, _generation);
    _readFlight = future;
    return future.whenComplete(() {
      if (identical(_readFlight, future)) _readFlight = null;
    });
  }

  Future<void> _load(VerifiedProfileOwner owner, int generation) async {
    final previous = state;
    _publish(
      CurrentAccountSummaryState(
        owner: owner,
        data: previous.data,
        capabilities: previous.capabilities,
        isLoading: true,
        networkRevision: previous.networkRevision,
      ),
    );
    late final DataReadResult<
      CurrentUserProfileData,
      CurrentUserProfileReadCapabilities
    >
    result;
    try {
      result = await ref
          .read(currentAccountSummaryRepositoryProvider)
          .load(
            CurrentAccountSummaryQuery(userId: owner.uid),
            cachePolicy: CacheLoadPolicy.networkFirst,
          );
    } on Object {
      result = const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        diagnosticMessage: 'current_account_summary_read_failed',
      );
    }
    if (!_isCurrent(owner.uid, generation) ||
        ref.read(verifiedProfileOwnerProvider) != owner) {
      return;
    }
    _lastLoadedOwner = owner;
    if (result
        case DataReadSuccess<
          CurrentUserProfileData,
          CurrentUserProfileReadCapabilities
        >(
          :final data,
          :final capabilities,
          :final metadata,
        )
        when data.identity.userId == owner.uid &&
            metadata.origin == DataReadOrigin.network &&
            metadata.freshness == DataReadFreshness.current) {
      _publish(
        CurrentAccountSummaryState(
          owner: owner,
          data: data,
          capabilities: capabilities,
          networkRevision: ++_networkRevision,
        ),
      );
      return;
    }
    final failure =
        result.failureOrNull ??
        const DataReadFailure<
          CurrentUserProfileData,
          CurrentUserProfileReadCapabilities
        >(
          kind: DataReadFailureKind.parse,
          code: 'account_summary_identity_invalid',
          diagnosticMessage: 'account_summary_identity_invalid',
        );
    final identityFailure =
        failure.kind == DataReadFailureKind.unauthorized ||
        failure.code == 'account_summary_identity_invalid' ||
        result is DataReadSuccess;
    if (identityFailure) {
      _identityBlockedOwner = owner;
      ref.read(accountDisplayControllerProvider.notifier).clear();
    }
    _publish(
      CurrentAccountSummaryState(
        owner: owner,
        data: identityFailure ? null : state.data,
        capabilities: identityFailure ? null : state.capabilities,
        failure: failure,
        networkRevision: previous.networkRevision,
      ),
    );
  }

  bool _isCurrent(String uid, int generation) =>
      ref.mounted && generation == _generation && state.displayUid == uid;
}
