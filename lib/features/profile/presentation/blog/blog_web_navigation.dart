import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// The package owns every protocol parameter. Browser return deliberately has
/// no write receipt: a page visit or a redirect cannot confirm a mutation.
Future<void> openBlogWebPage(
  BuildContext context,
  WidgetRef ref, {
  required Uri? Function(UserBlogNavigation navigation) destination,
  String? expectedActor,
  bool replaceCurrent = false,
}) async {
  if (expectedActor != null &&
      ref.read(blogAccountIdProvider) != expectedActor) {
    return;
  }
  final navigation = ref.read(userBlogNavigationProvider);
  final uri = navigation == null ? null : destination(navigation);
  if (uri == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).commonRequestError)),
    );
    return;
  }
  final route = ref.read(forumWebViewRouteFactoryProvider)(
    ForumWebViewLaunchConfig(
      initialUri: uri,
      popOnRootBack: true,
      expectedAccountId: expectedActor,
    ),
  );
  final navigator = Navigator.of(context);
  if (replaceCurrent) {
    // Replacing discards the native form ticket. Returning from a browser form
    // must not make a stale native editor eligible to overwrite browser edits.
    await navigator.pushReplacement<Object?, Object?>(route);
  } else {
    await navigator.push(route);
  }
}
