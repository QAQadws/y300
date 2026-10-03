import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

final class ForumUserProfilePageState {
  const ForumUserProfilePageState({
    this.data,
    this.capabilities,
    this.metadata,
    this.failure,
    this.isRefreshing = false,
    this.ownerUid,
    this.ownerRevision,
  });

  final ForumUserProfileData? data;
  final ForumUserProfileReadCapabilities? capabilities;
  final DataReadMetadata? metadata;
  final DataReadFailure<ForumUserProfileData, ForumUserProfileReadCapabilities>?
  failure;
  final bool isRefreshing;

  /// The viewer session that owns this read, including public profile actions.
  final String? ownerUid;
  final int? ownerRevision;

  bool belongsToSession(VerifiedProfileOwner? owner) =>
      ownerUid == owner?.uid && ownerRevision == owner?.revision;

  ForumUserProfilePageState copyWith({
    ForumUserProfileData? data,
    ForumUserProfileReadCapabilities? capabilities,
    DataReadMetadata? metadata,
    DataReadFailure<ForumUserProfileData, ForumUserProfileReadCapabilities>?
    failure,
    bool? isRefreshing,
    bool clearFailure = false,
    String? ownerUid,
    int? ownerRevision,
  }) => ForumUserProfilePageState(
    data: data ?? this.data,
    capabilities: capabilities ?? this.capabilities,
    metadata: metadata ?? this.metadata,
    failure: clearFailure ? null : (failure ?? this.failure),
    isRefreshing: isRefreshing ?? this.isRefreshing,
    ownerUid: ownerUid ?? this.ownerUid,
    ownerRevision: ownerRevision ?? this.ownerRevision,
  );
}

final userProfileProvider = AsyncNotifierProvider.autoDispose
    .family<UserProfilePageController, ForumUserProfilePageState, String>(
      UserProfilePageController.new,
    );

final myUserProfileProvider =
    AsyncNotifierProvider.autoDispose<
      MyUserProfilePageController,
      ForumUserProfilePageState
    >(MyUserProfilePageController.new);

final class UserProfilePageController extends _ProfilePageController {
  UserProfilePageController(String userId) : super(userId: userId);
}

final class MyUserProfilePageController extends _ProfilePageController {
  MyUserProfilePageController() : super(selfOnly: true);
}

/// A profile read is owned by both its route and its authenticated viewer.
/// Public pages also rebuild on account changes because their actions can vary.
abstract class _ProfilePageController
    extends AsyncNotifier<ForumUserProfilePageState> {
  _ProfilePageController({String? userId, bool selfOnly = false})
    : _userId = userId,
      _selfOnly = selfOnly;

  final String? _userId;
  final bool _selfOnly;
  int _generation = 0;
  ForumRequestCancellation? _cancellation;
  Future<ForumUserProfilePageState>? _pending;

  @override
  Future<ForumUserProfilePageState> build() {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    _cancel();
    ref.onDispose(_cancel);
    if (_selfOnly && owner == null) {
      return Future.value(const ForumUserProfilePageState());
    }
    return _start(owner, previous: null, refresh: false);
  }

  Future<void> refresh() {
    if (!ref.mounted) return Future.value();
    final pending = _pending;
    if (pending != null) return pending.then((_) {});
    final owner = ref.read(verifiedProfileOwnerProvider);
    final previous = state.asData?.value;
    if ((_selfOnly && owner == null) ||
        previous == null ||
        !previous.belongsToSession(owner)) {
      return Future.value();
    }
    // Install the flight before publishing, so listener-triggered refreshes
    // share this request instead of starting a second one.
    final future = _start(owner, previous: previous, refresh: true);
    final generation = _generation;
    state = AsyncData(
      previous.copyWith(isRefreshing: true, clearFailure: true),
    );
    return future.then((next) {
      if (_isCurrent(owner, generation)) state = AsyncData(next);
    });
  }

  Future<ForumUserProfilePageState> _start(
    VerifiedProfileOwner? owner, {
    required ForumUserProfilePageState? previous,
    required bool refresh,
  }) {
    final generation = ++_generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    final completion = Completer<ForumUserProfilePageState>();
    _pending = completion.future;
    unawaited(
      _load(owner, generation, cancellation, previous, refresh).then((next) {
        if (_isCurrent(owner, generation)) {
          _pending = null;
          _cancellation = null;
        }
        completion.complete(next);
      }),
    );
    return completion.future;
  }

  Future<ForumUserProfilePageState> _load(
    VerifiedProfileOwner? owner,
    int generation,
    ForumRequestCancellation cancellation,
    ForumUserProfilePageState? previous,
    bool refresh,
  ) async {
    final userId = _userId ?? owner!.uid;
    final self = _selfOnly || owner?.uid == userId;
    DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>
    result;
    if (!RegExp(r'^[1-9]\d*$').hasMatch(userId)) {
      result =
          const DataReadFailure<
            ForumUserProfileData,
            ForumUserProfileReadCapabilities
          >(
            kind: DataReadFailureKind.parse,
            diagnosticMessage: 'profile_invalid_user',
          );
    } else {
      try {
        result = await ref
            .read(forumUserProfileRepositoryProvider)
            .load(
              ForumUserProfileQuery(
                userId: userId,
                viewerUserId: owner?.uid,
                view: self
                    ? ForumUserProfileView.self
                    : ForumUserProfileView.public,
              ),
              cachePolicy: self || refresh
                  ? CacheLoadPolicy.networkFirst
                  : CacheLoadPolicy.cacheFirst,
              cancellation: cancellation,
            );
      } on Object {
        result =
            const DataReadFailure<
              ForumUserProfileData,
              ForumUserProfileReadCapabilities
            >(
              kind: DataReadFailureKind.unknown,
              diagnosticMessage: 'profile_read_failed',
            );
      }
    }
    if (!_isCurrent(owner, generation) || cancellation.isCancelled) {
      return const ForumUserProfilePageState();
    }
    if (result case DataReadSuccess(
      :final data,
      :final capabilities,
      :final metadata,
    )) {
      final matchingViewer =
          data.viewerUserId == null || data.viewerUserId == owner?.uid;
      final verifiedProvenance =
          !self ||
          (metadata.origin == DataReadOrigin.network &&
              metadata.freshness == DataReadFreshness.current);
      if (data.identity.userId == userId &&
          matchingViewer &&
          verifiedProvenance) {
        return ForumUserProfilePageState(
          data: data,
          capabilities: capabilities,
          metadata: metadata,
          ownerUid: owner?.uid,
          ownerRevision: owner?.revision,
        );
      }
      result =
          const DataReadFailure<
            ForumUserProfileData,
            ForumUserProfileReadCapabilities
          >(
            kind: DataReadFailureKind.parse,
            diagnosticMessage: 'profile_identity_or_provenance_unverified',
          );
    }
    final failure = result.failureOrNull!;
    final retain =
        previous?.belongsToSession(owner) == true &&
        (failure.kind == DataReadFailureKind.network ||
            failure.kind == DataReadFailureKind.timeout);
    return ForumUserProfilePageState(
      data: retain ? previous?.data : null,
      capabilities: retain ? previous?.capabilities : null,
      metadata: retain ? previous?.metadata : null,
      failure: failure,
      ownerUid: owner?.uid,
      ownerRevision: owner?.revision,
    );
  }

  bool _isCurrent(VerifiedProfileOwner? owner, int generation) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(verifiedProfileOwnerProvider) == owner;

  void _cancel() {
    ++_generation;
    _cancellation?.cancel();
    _cancellation = null;
    _pending = null;
  }
}
