import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/friend_routes.dart';
import 'package:y300/app/navigation/forum_link_routes.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/messages/presentation/new_private_message_page.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/presentation/services/thread_post_route_launcher.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';

typedef PrivateConversationRouteFactory =
    Route<void> Function(ForumConversationTarget target, {String title});

class MessageCenterDestination extends ConsumerWidget {
  const MessageCenterDestination({
    super.key,
    this.isActive = true,
    this.initialTab = MessageCenterTab.messages,
  });
  final bool isActive;
  final MessageCenterTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MessageCenterPage(
    isActive: isActive,
    initialTab: initialTab,
    onOpenLink: ref.watch(messageLinkOpenerProvider),
    onOpenUser: (context, userId) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => UserProfilePage(uid: userId)),
    ),
    onOpenConversation: (context, target, title) => Navigator.of(context).push(
      ref.read(privateConversationRouteFactoryProvider)(target, title: title),
    ),
  );
}

/// Cross-feature destinations stay in app composition; message widgets only
/// receive a link callback and source-neutral conversation identities.
final privateConversationRouteFactoryProvider =
    Provider<PrivateConversationRouteFactory>(
      (ref) =>
          (target, {title = ''}) => MaterialPageRoute<void>(
            builder: (_) => PrivateConversationPage(
              target: target,
              title: title,
              onOpenLink: ref.read(messageLinkOpenerProvider),
            ),
          ),
    );

final messageLinkOpenerProvider = Provider<MessageLinkOpener>((ref) {
  final postSessions = <ModalRoute<dynamic>?, ThreadPostNavigationSession>{};
  var active = true;
  ref.onDispose(() {
    active = false;
    for (final session in postSessions.values) {
      session.dispose();
    }
    postSessions.clear();
  });

  ThreadPostNavigationSession postSession(ModalRoute<dynamic>? route) {
    return postSessions.putIfAbsent(route, () {
      final session = ThreadPostNavigationSession();
      if (route != null) {
        // Keep single-flight navigation scoped to the originating message page.
        unawaited(
          route.completed.then((_) {
            if (identical(postSessions[route], session)) {
              postSessions.remove(route);
            }
            session.dispose();
          }),
        );
      }
      return session;
    });
  }

  Future<void> open(BuildContext context, String url) async {
    if (!active || !context.mounted) return;
    final sourceRoute = ModalRoute.of(context);
    if (sourceRoute != null && !sourceRoute.isCurrent) return;
    try {
      const resolver = YamiboForumLinkResolver();
      final destination = resolver.resolveForViewer(
        url,
        readViewerUserId: () => ref.read(verifiedProfileOwnerProvider)?.uid,
      );
      if (destination == null ||
          !{'https', 'http'}.contains(destination.uri.scheme)) {
        return;
      }
      final uri = destination.uri;
      final query = uri.queryParameters;
      if (destination.kind != YamiboForumLinkKind.threadPost) {
        postSessions[sourceRoute]?.invalidate();
      }
      Widget? page;
      switch (destination.kind) {
        case YamiboForumLinkKind.home:
        case YamiboForumLinkKind.forumDisplay:
        case YamiboForumLinkKind.search:
          page = nativeForumLinkPage(destination);
        case YamiboForumLinkKind.thread:
          page = ThreadDetailPage(
            tid: destination.tid!,
            initialPage: destination.page ?? 1,
          );
        case YamiboForumLinkKind.threadPost:
          await launchThreadPostRoute(
            context: context,
            session: postSession(sourceRoute),
            resolver: ref.read(threadPostRouteResolverProvider),
            target: ThreadPostTarget.fromLink(
              tid: destination.tid!,
              pid: destination.pid!,
              sourceUri: uri,
              pageHint: destination.page,
            ),
            isCurrent: () => active,
          );
          return;
        case YamiboForumLinkKind.tagThreadPage:
          page = YamiboTagThreadPage(
            tagId: destination.tagId!,
            page: destination.page ?? 1,
          );
        case YamiboForumLinkKind.userThreadDirectory:
          page = UserThreadPage(
            userId: destination.userId,
            initialType: destination.userThreadType!,
            initialPage: destination.page ?? 1,
          );
        case YamiboForumLinkKind.friendFeed:
          page = MyFriendsDestination(
            initialScope: destination.friendScope!,
            initialPage: destination.page ?? 1,
          );
        case YamiboForumLinkKind.managedWebView:
          if (uri.path == '/home.php' &&
              query['mod'] == 'space' &&
              ((query['do'] == 'notice' &&
                      !query.containsKey('ignore') &&
                      (query['view'] == null || query['view'] == 'all')) ||
                  (query['do'] == 'pm' &&
                      (query['subop'] == null || query['subop'] == '') &&
                      (query['filter'] == null ||
                          query['filter'] == 'privatepm')))) {
            page = MessageCenterDestination(
              initialTab: query['do'] == 'notice'
                  ? MessageCenterTab.notifications
                  : MessageCenterTab.messages,
            );
          } else if (uri.path == '/home.php' &&
              query['mod'] == 'space' &&
              query['do'] == 'pm' &&
              query['subop'] == 'view') {
            final group = query['type'] == '1';
            final id = query[group ? 'plid' : 'touid'];
            if (_positiveId(id)) {
              page = PrivateConversationPage(
                target: group
                    ? ForumConversationTarget.group(id!)
                    : ForumConversationTarget.direct(id!),
                onOpenLink: (context, url) => unawaited(open(context, url)),
              );
            }
          } else if (uri.path == '/home.php' &&
              query['mod'] == 'spacecp' &&
              query['ac'] == 'pm' &&
              (query['op'] == null || query['op'] == '')) {
            final id = query['touid'];
            page = _positiveId(id)
                ? PrivateConversationPage(
                    target: ForumConversationTarget.direct(id!),
                    onOpenLink: (context, url) => unawaited(open(context, url)),
                  )
                : const NewPrivateMessagePage();
          } else {
            final profileId =
                uri.path == '/home.php' &&
                    query['mod'] == 'space' &&
                    (!query.containsKey('do') || query['do'] == 'profile')
                ? query['uid']
                : RegExp(
                    r'^/space-uid-(\d+)\.html$',
                  ).firstMatch(uri.path)?.group(1);
            if (_positiveId(profileId)) page = UserProfilePage(uid: profileId!);
          }
          if (page == null) {
            unawaited(
              Navigator.of(context).push(
                ref.read(forumWebViewRouteFactoryProvider)(
                  ForumWebViewLaunchConfig(
                    initialUri: uri,
                    popOnRootBack: true,
                  ),
                ),
              ),
            );
            return;
          }
        case YamiboForumLinkKind.external:
          final opened = await ref
              .read(forumWebViewExternalLauncherProvider)
              .launch(uri);
          if (!opened && context.mounted) _showLinkFailure(context);
          return;
      }
      if (context.mounted) {
        unawaited(
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => page!)),
        );
      }
    } on Object {
      if (context.mounted) _showLinkFailure(context);
    }
  }

  return (context, url) => unawaited(open(context, url));
});

bool _positiveId(String? value) =>
    value != null && RegExp(r'^[1-9]\d*$').hasMatch(value);

void _showLinkFailure(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).messageLinkFailed)),
    );
