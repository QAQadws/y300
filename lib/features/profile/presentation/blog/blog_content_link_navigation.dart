import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// The source resolves native blog identities; existing browser boundaries
/// handle other forum flows and external links. A link never proves a write.
Future<void> openBlogContentLink(
  BuildContext context,
  WidgetRef ref,
  String rawUrl, {
  Uri? baseUri,
}) async {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) return;
  final actor = ref.read(blogAccountIdProvider);
  final owner = ref.read(blogMutationBusProvider);
  final navigation = ref.read(userBlogNavigationProvider);
  final destination = navigation?.resolveReadReference(
    rawUrl,
    baseUri: baseUri,
    actorUserId: actor,
  );
  final Widget? page = switch (destination) {
    UserBlogDirectoryReference(:final query) => ProfileBlogPage.fromQuery(
      query,
    ),
    UserBlogDetailReference(:final query, :final focusComments) =>
      ProfileBlogDetailPage(
        ownerUserId: query.ownerUserId,
        blogId: query.blogId,
        initialPage: query.page,
        commentId: query.commentId,
        lastCommentPage: query.lastCommentPage,
        focusComments: focusComments,
      ),
    UserBlogAuthorReference(:final userId) => UserProfilePage(uid: userId),
    null => null,
  };
  if (page != null) {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
    return;
  }

  bool stillCurrent() =>
      context.mounted &&
      identical(ref.read(blogMutationBusProvider), owner) &&
      ModalRoute.of(context)?.isCurrent != false;
  void failed() {
    if (!stillCurrent()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).forumWebViewOpenExternalFailed,
        ),
      ),
    );
  }

  try {
    final raw = Uri.tryParse(rawUrl.trim().replaceAll('&amp;', '&'));
    if (raw == null || rawUrl.trim().isEmpty) {
      failed();
      return;
    }
    final browser = ref.read(forumWebViewNavigatorProvider);
    final uri = (baseUri ?? browser.homeUri).resolveUri(raw);
    if (!{'https', 'http', 'mailto'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      failed();
      return;
    }
    final samePort =
        uri.port == browser.homeUri.port ||
        (!uri.hasPort && !browser.homeUri.hasPort);
    if (browser.isManagedSite(uri) && samePort) {
      await Navigator.of(context).push(
        ref.read(forumWebViewRouteFactoryProvider)(
          ForumWebViewLaunchConfig(
            initialUri: uri,
            popOnRootBack: true,
            expectedAccountId: actor,
          ),
        ),
      );
    } else if (!await ref
        .read(forumWebViewExternalLauncherProvider)
        .launch(uri)) {
      failed();
    }
  } catch (_) {
    failed();
  }
}
