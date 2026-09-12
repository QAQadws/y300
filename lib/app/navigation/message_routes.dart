import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/messages/presentation/new_private_message_page.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';

typedef PrivateConversationRouteFactory =
    Route<void> Function(ForumConversationTarget target, {String title});

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
  Future<void> open(BuildContext context, String url) async {
    if (!context.mounted) return;
    final sourceRoute = ModalRoute.of(context);
    if (sourceRoute != null && !sourceRoute.isCurrent) return;
    try {
      final destination = const YamiboForumLinkResolver().resolve(url);
      if (destination == null ||
          !{'https', 'http'}.contains(destination.uri.scheme)) {
        return;
      }
      final uri = destination.uri;
      final query = uri.queryParameters;
      Widget? page;
      switch (destination.kind) {
        case YamiboForumLinkKind.thread:
          page = ThreadDetailPage(
            tid: destination.tid!,
            initialPage: destination.page ?? 1,
          );
        case YamiboForumLinkKind.threadPost:
          var tid = destination.tid!;
          var pid = destination.pid!;
          var targetPage = destination.page;
          if (targetPage == null) {
            final result = await ref
                .read(threadPostLocatorProvider)
                .locate(tid: tid, pid: pid, sourceUri: uri);
            if (!context.mounted ||
                (sourceRoute != null && !sourceRoute.isCurrent)) {
              return;
            }
            if (result case ApiSuccess<ThreadPostLocation>(:final data)) {
              tid = data.tid;
              pid = data.pid;
              targetPage = data.page;
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).threadDetailFloorLocatorFailed,
                  ),
                ),
              );
            }
          }
          page = ThreadDetailPage(
            tid: tid,
            initialPage: targetPage ?? 1,
            targetPid: pid,
          );
        case YamiboForumLinkKind.tagThreadPage:
          page = YamiboTagThreadPage(
            tagId: destination.tagId!,
            page: destination.page ?? 1,
          );
        case YamiboForumLinkKind.managedWebView:
          if (uri.path == '/home.php' &&
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
              query['ac'] == 'pm') {
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
                    !query.containsKey('do')
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
