import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/forum_link_routes.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/domain/services/thread_post_route_resolver.dart';
import 'package:y300/features/thread/presentation/services/thread_post_route_launcher.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

final forumLinkOpenerProvider = Provider<ForumLinkOpener>((ref) {
  var active = true;
  var identity = Object();
  final sessions = ref.read(yamiboSessionStoreProvider);
  // Synchronous identity notifications retire old navigation even before
  // Riverpod publishes the shared verified-owner revision. This token grants
  // no authentication and does not start validation for ordinary links.
  final subscription = sessions.identityChanges.listen((_) {
    identity = Object();
  });
  ref.onDispose(() {
    active = false;
    unawaited(subscription.cancel());
  });
  return ForumLinkOpener(
    readViewerUserId: () => ref.read(verifiedSessionOwnerProvider)?.uid,
    readOwner: () => identity,
    isActive: () => active,
    nativePage: (destination) =>
        ref.read(nativeForumLinkPageFactoryProvider)(destination),
    webViewRoute: (config) =>
        ref.read(forumWebViewRouteFactoryProvider)(config),
    externalLauncher: () => ref.read(forumWebViewExternalLauncherProvider),
    postResolver: () => ref.read(threadPostRouteResolverProvider),
  );
});

/// App-owned dispatch. Callers retain their existing navigation session and
/// provide source validity; renderer callbacks only pass the clicked URL.
final class ForumLinkOpener {
  ForumLinkOpener({
    required this.readViewerUserId,
    required this.readOwner,
    required this.isActive,
    required this.nativePage,
    required this.webViewRoute,
    required this.externalLauncher,
    required this.postResolver,
  });

  final String? Function() readViewerUserId;
  final Object? Function() readOwner;
  final bool Function() isActive;
  final Widget? Function(YamiboForumLinkDestination) nativePage;
  final ForumWebViewRouteFactory webViewRoute;
  final ForumWebViewExternalLauncher Function() externalLauncher;
  final ThreadPostRouteResolver Function() postResolver;
  final _sessionOwners = Expando<Object>();

  Future<void> open({
    required BuildContext context,
    required String url,
    required ThreadPostNavigationSession session,
    required bool Function() isCurrent,
    Future<void> Function(String url)? onCopyLink,
  }) async {
    if (!isActive() || !context.mounted || !isCurrent()) return;
    final sourceRoute = ModalRoute.of(context);
    if (sourceRoute?.isCurrent == false) return;
    final owner = readOwner();
    // Reissuing the same target after an account change must not join an old
    // owner's pending request. Weak keys do not retain departed source pages.
    if (_sessionOwners[session] != (owner,)) {
      session.invalidate();
      _sessionOwners[session] = (owner,);
    }
    bool current() =>
        isActive() && context.mounted && isCurrent() && owner == readOwner();
    bool sourceCurrent() => current() && sourceRoute?.isCurrent != false;
    bool Function() failureCurrent = sourceCurrent;

    void failure() {
      if (!failureCurrent()) return;
      final l10n = AppLocalizations.of(context);
      showTransientSnackBar(
        context,
        l10n.messageLinkFailed,
        action: SnackBarAction(
          label: l10n.threadDetailCopyLink,
          onPressed: () {
            if (!sourceCurrent()) return;
            unawaited(
              (onCopyLink?.call(url) ??
                      Clipboard.setData(ClipboardData(text: url)))
                  .catchError((Object _) {}),
            );
          },
        ),
      );
    }

    try {
      final destination = const YamiboForumLinkResolver().resolveForViewer(
        url,
        readViewerUserId: readViewerUserId,
      );
      if (destination == null ||
          !{'http', 'https'}.contains(destination.uri.scheme) ||
          destination.uri.host.isEmpty) {
        session.invalidate();
        failure();
        return;
      }
      if (destination.kind == YamiboForumLinkKind.threadPost) {
        // The floor launcher already owns single-flight and route lifetime;
        // nesting session.run here would replace its request generation.
        await launchThreadPostRoute(
          context: context,
          session: session,
          resolver: postResolver(),
          target: ThreadPostTarget.fromLink(
            tid: destination.tid!,
            pid: destination.pid!,
            sourceUri: destination.uri,
            pageHint: destination.page,
          ),
          isCurrent: current,
        );
        return;
      }
      await session.run(
        key: (destination.kind, destination.uri.toString()),
        isCurrent: current,
        action: (requestCurrent) async {
          failureCurrent = () =>
              requestCurrent() && sourceRoute?.isCurrent != false;
          if (!requestCurrent() || sourceRoute?.isCurrent == false) return;
          if (destination.kind == YamiboForumLinkKind.external) {
            final opened = await externalLauncher().launch(destination.uri);
            if (!opened && requestCurrent()) failure();
            return;
          }
          if (destination.kind == YamiboForumLinkKind.managedWebView) {
            await Navigator.of(context).push(
              webViewRoute(
                ForumWebViewLaunchConfig(
                  initialUri: destination.uri,
                  popOnRootBack: true,
                  navigationPolicy: ForumWebViewNavigationPolicy.keepWebView,
                ),
              ),
            );
            return;
          }
          final page = nativePage(destination);
          if (page == null) {
            failure();
            return;
          }
          await Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => page));
        },
      );
    } on Object {
      failure();
    }
  }
}
