import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/profile/presentation/profile_action_navigation.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

/// Compatibility entry for callers that explicitly need the forum fallback.
/// The browser remains bound to the same verified account as the caller.
Future<Object?> openMyProfileForumPage({
  required BuildContext context,
  required WidgetRef ref,
  required String userId,
}) {
  final owner = ref.read(verifiedProfileOwnerProvider);
  return openProfileForumPage(
    context: context,
    ref: ref,
    userId: userId,
    isMyProfile: true,
    isCurrentOwner: () =>
        owner != null && ref.read(verifiedProfileOwnerProvider) == owner,
  );
}
