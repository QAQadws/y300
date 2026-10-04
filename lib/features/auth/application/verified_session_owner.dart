import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
import 'package:y300/features/auth/domain/models/verified_session_owner.dart';

export 'package:y300/features/auth/domain/models/verified_session_owner.dart';

/// The session store emits identity transitions, including logout and a later
/// login to the same UID. Keeping this generation shared prevents old results
/// from being accepted by account-bound consumers.
final sessionRevisionProvider = StreamProvider.autoDispose<int>((ref) {
  final changes = StreamController<int>(sync: true);
  var revision = 0;
  final subscription = ref
      .watch(yamiboSessionStoreProvider)
      .identityChanges
      .listen((_) => changes.add(++revision));
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(changes.close());
  });
  changes.add(revision);
  return changes.stream;
});

final verifiedSessionOwnerProvider =
    Provider.autoDispose<VerifiedSessionOwner?>(
      (ref) => verifiedSessionOwner(
        ref.watch(authSessionControllerProvider),
        ref.watch(sessionRevisionProvider),
        ref.read(yamiboSessionStoreProvider).readCurrent(),
      ),
    );

VerifiedSessionOwner? verifiedSessionOwner(
  AsyncValue<AuthSessionViewState> auth,
  AsyncValue<int> sessionRevision,
  YamiboSessionSnapshot? snapshot,
) {
  final session = auth.asData?.value;
  final revision = sessionRevision.asData?.value;
  final uid = session?.uid.trim() ?? '';
  if (session == null ||
      revision == null ||
      !session.isLoggedIn ||
      session.isLoggingOut ||
      (int.tryParse(uid) ?? 0) < 1) {
    return null;
  }
  if (snapshot != null &&
      (!snapshot.isLoggedIn || snapshot.uid.trim() != uid)) {
    return null;
  }
  // An empty initial store may follow an independently verified API session.
  // After a transition, an empty store means that owner was cleared.
  if (snapshot == null && revision > 0) return null;
  return (uid: uid, revision: revision);
}
