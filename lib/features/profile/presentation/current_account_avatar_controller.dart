import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/profile/presentation/current_account_summary_controller.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

class CurrentAccountAvatarState {
  const CurrentAccountAvatarState({
    this.uid,
    this.localPath,
    this.useDefault = false,
    this.animate = false,
  });
  final String? uid;
  final String? localPath;
  final bool useDefault;
  final bool animate;
}

final currentAccountAvatarControllerProvider =
    NotifierProvider.autoDispose<
      CurrentAccountAvatarController,
      CurrentAccountAvatarState
    >(CurrentAccountAvatarController.new);

String currentAccountAvatarCacheKey(String uid) =>
    '${Uri.parse(AppConfig.siteBaseUrl).origin}:account.avatar:$uid';

class CurrentAccountAvatarController
    extends Notifier<CurrentAccountAvatarState> {
  int _generation = 0;
  ({String? uid, int revision})? _lastAttempt;
  CurrentAccountAvatarState _last = const CurrentAccountAvatarState();

  @override
  CurrentAccountAvatarState build() {
    final summary = ref.watch(
      currentAccountSummaryControllerProvider.select(
        (s) => (
          uid: s.displayUid,
          owner: s.owner,
          url:
              s.capabilities?.supports(
                    CurrentUserProfileCapability.avatarReference,
                  ) ==
                  true
              ? s.data?.avatarUrl
              : null,
          hasData: s.data != null,
          revision: s.networkRevision,
          identityFailure:
              s.failure?.kind == DataReadFailureKind.unauthorized ||
              s.failure?.code == 'account_summary_identity_invalid',
        ),
      ),
    );
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    if (_last.uid != summary.uid || summary.identityFailure) {
      _last = CurrentAccountAvatarState(
        uid: summary.identityFailure ? null : summary.uid,
      );
    }
    if (summary.uid != null && !summary.identityFailure) {
      final attempt = (uid: summary.uid, revision: summary.revision);
      final refresh =
          summary.owner != null &&
          summary.hasData &&
          summary.revision > 0 &&
          _lastAttempt != attempt;
      if (refresh) _lastAttempt = attempt;
      unawaited(
        Future<void>.microtask(
          () => _load(
            summary.uid!,
            summary.url,
            summary.hasData,
            refresh,
            generation,
          ),
        ),
      );
    }
    return _last;
  }

  bool _current(int generation) => ref.mounted && _generation == generation;

  void _publish(CurrentAccountAvatarState value) {
    _last = value;
    state = value;
  }

  Future<void> _load(
    String uid,
    String? url,
    bool hasData,
    bool refresh,
    int generation,
  ) async {
    if (!_current(generation)) return;
    try {
      final service = ref.read(imageCacheServiceProvider);
      final key = currentAccountAvatarCacheKey(uid);
      if (isForumDefaultAvatarUrl(url)) {
        _publish(
          CurrentAccountAvatarState(
            uid: uid,
            useDefault: true,
            animate: state.localPath != null,
          ),
        );
        return;
      }
      if (state.localPath == null) {
        final cached = await service.getCached(key);
        if (!_current(generation)) return;
        if (cached?.success == true && cached?.localPath != null) {
          _publish(
            CurrentAccountAvatarState(uid: uid, localPath: cached!.localPath),
          );
        }
      }
      if (!refresh) return;
      if (isForumDefaultOrUnsupportedAvatarUrl(url)) {
        if (state.localPath == null && hasData) {
          _publish(CurrentAccountAvatarState(uid: uid, useDefault: true));
        }
        return;
      }
      if (service is! ImageCacheRevalidator) return;
      final result = await (service as ImageCacheRevalidator).revalidate(
        ImageCacheRequest(
          cacheKey: key,
          sourceUrl: url!,
          referer: ref.read(forumImageRefererProvider),
          ownerType: ImageCacheOwnerType.profile,
          ownerId: uid,
          role: ImageCacheRole.avatar,
          retentionClass: ImageRetentionClass.sticky,
        ),
        isCurrent: () => _current(generation),
      );
      if (!_current(generation)) return;
      if (result.success && result.localPath != null) {
        if (result.localPath == state.localPath) return;
        _publish(
          CurrentAccountAvatarState(
            uid: uid,
            localPath: result.localPath,
            animate: true,
          ),
        );
      } else if (state.localPath == null) {
        _publish(CurrentAccountAvatarState(uid: uid, useDefault: true));
      }
    } on Object {
      if (_current(generation) && state.localPath == null && refresh) {
        _publish(CurrentAccountAvatarState(uid: uid, useDefault: true));
      }
    }
  }
}
