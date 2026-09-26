import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

final class CurrentAccountSummaryState {
  const CurrentAccountSummaryState({
    this.owner,
    this.data,
    this.capabilities,
    this.failure,
    this.isLoading = false,
  });

  final VerifiedProfileOwner? owner;
  final CurrentUserProfileData? data;
  final CurrentUserProfileReadCapabilities? capabilities;
  final DataReadFailure<
    CurrentUserProfileData,
    CurrentUserProfileReadCapabilities
  >?
  failure;
  final bool isLoading;
}

final currentAccountSummaryControllerProvider =
    NotifierProvider.autoDispose<
      CurrentAccountSummaryController,
      CurrentAccountSummaryState
    >(CurrentAccountSummaryController.new);

/// An in-memory account summary scoped to a verified session and its readers.
final class CurrentAccountSummaryController
    extends Notifier<CurrentAccountSummaryState> {
  int _generation = 0;
  Future<void>? _readFlight;

  @override
  CurrentAccountSummaryState build() {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final generation = ++_generation;
    _readFlight = null;
    ref.onDispose(() => _generation++);
    if (owner != null) {
      unawaited(
        Future<void>.microtask(() async {
          if (_isCurrent(owner, generation) &&
              _readFlight == null &&
              state.data == null &&
              state.failure == null) {
            await refresh();
          }
        }),
      );
    }
    return CurrentAccountSummaryState(owner: owner, isLoading: owner != null);
  }

  Future<void> refresh() {
    final owner = state.owner;
    if (owner == null) return Future<void>.value();
    if (_readFlight case final pending?) return pending;
    final future = _load(owner, _generation);
    _readFlight = future;
    return future.whenComplete(() {
      if (identical(_readFlight, future)) _readFlight = null;
    });
  }

  Future<void> _load(VerifiedProfileOwner owner, int generation) async {
    final previous = state;
    state = CurrentAccountSummaryState(
      owner: owner,
      data: previous.data,
      capabilities: previous.capabilities,
      isLoading: true,
    );
    late final DataReadResult<
      CurrentUserProfileData,
      CurrentUserProfileReadCapabilities
    >
    result;
    try {
      result = await ref
          .read(currentUserProfileRepositoryProvider)
          .load(
            const CurrentUserProfileQuery(),
            cachePolicy: CacheLoadPolicy.networkFirst,
          );
    } on Object {
      result = const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        diagnosticMessage: 'current_account_summary_read_failed',
      );
    }
    // The current-profile contract has no cancellation signal. Discard replies
    // after logout, account changes, same-UID relogin, or provider disposal.
    if (!_isCurrent(owner, generation)) return;
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
      state = CurrentAccountSummaryState(
        owner: owner,
        data: data,
        capabilities: capabilities,
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
          diagnosticMessage:
              'current_account_summary_identity_or_provenance_unverified',
        );
    final canRetain =
        previous.owner == owner &&
        (failure.kind == DataReadFailureKind.network ||
            failure.kind == DataReadFailureKind.timeout);
    state = CurrentAccountSummaryState(
      owner: owner,
      data: canRetain ? previous.data : null,
      capabilities: canRetain ? previous.capabilities : null,
      failure: failure,
    );
  }

  bool _isCurrent(VerifiedProfileOwner owner, int generation) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(verifiedProfileOwnerProvider) == owner;
}
