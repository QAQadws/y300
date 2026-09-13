import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_plain_text_extractor.dart';
import 'package:y300/features/thread/domain/services/thread_floor_link_builder.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

class ThreadPostNavigation {
  const ThreadPostNavigation({
    required this.context,
    required this.ref,
    required this.tid,
    required this.imageReferer,
    required this.isCurrent,
  });
  final BuildContext context;
  final WidgetRef ref;
  final String tid;
  final String? imageReferer;
  final bool Function() isCurrent;
  bool get mounted => context.mounted && isCurrent();
  ThreadFloorLinkBuilder get _floorLinkBuilder => ThreadFloorLinkBuilder();
  void _showSnackBar(String text) {
    if (context.mounted && isCurrent()) showTransientSnackBar(context, text);
  }

  void openImages(ThreadPost post, ThreadPostImageOpenRequest request) {
    final readerRequest = request.readerRequest;
    if (readerRequest == null || readerRequest.continuousImages.isEmpty) {
      copyUrl(
        '${post.number}# ${AppLocalizations.of(context).threadDetailImageLink}',
        request.image.url,
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadImageReaderPage(
          request: readerRequest,
          imageReferer: imageReferer,
        ),
      ),
    );
  }

  Future<void> copyFloorLink(ThreadPost sourcePost) async {
    final authSession = ref.read(authSessionControllerProvider).asData?.value;
    final link = _floorLinkBuilder.build(
      tid: tid,
      pid: sourcePost.pid,
      fromUid: authSession?.isLoggedIn == true ? authSession?.uid : null,
    );
    if (link == null) {
      _showSnackBar(
        AppLocalizations.of(context).threadDetailCopyFloorLinkFailed,
      );
      return;
    }
    await copyUrl(
      AppLocalizations.of(context).threadDetailFloorLink,
      link.toString(),
    );
  }

  Future<void> copyPlainText(ThreadPost post, ThreadPostBodyRenderPlan plan) {
    final text = const ThreadPostBodyPlainTextExtractor().extract(
      plan.document,
    );
    return copyUrl(
      '${post.number}# ${AppLocalizations.of(context).threadDetailPostBody}',
      text,
    );
  }

  void copyImageUrl(ThreadPost post, ForumHtmlImageRequest request) {
    copyUrl(
      '${post.number}# ${AppLocalizations.of(context).threadDetailImageLink}',
      request.url,
    );
  }

  void openAuthor(ThreadPost post) {
    final uid = post.authorId.trim();
    if (uid.isEmpty) {
      _showSnackBar(AppLocalizations.of(context).threadDetailUidMissing);
      return;
    }
    openManagedWebView(_authorProfileUri(uid));
  }

  void openCommentAuthor(ThreadPostCommentEntry comment) {
    final uid = _commentAuthorUid(comment);
    if (uid == null || uid.isEmpty) {
      _showSnackBar(AppLocalizations.of(context).threadDetailUidMissing);
      return;
    }
    openManagedWebView(_authorProfileUri(uid));
  }

  String? _commentAuthorUid(ThreadPostCommentEntry comment) {
    final authorId = comment.authorId?.trim();
    if (authorId != null && authorId.isNotEmpty) {
      return authorId;
    }
    final authorUrl = comment.authorUrl?.trim();
    if (authorUrl == null || authorUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(authorUrl);
    final uid = uri?.queryParameters['uid']?.trim();
    if (uid != null && uid.isNotEmpty) {
      return uid;
    }
    final match = RegExp(
      r'space-uid-(\d+)',
      caseSensitive: false,
    ).firstMatch(authorUrl);
    return match?.group(1);
  }

  Uri _authorProfileUri(String uid) {
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': uid,
        'mobile': '2',
      },
    );
  }

  void openLink(String url) {
    final destination = const YamiboForumLinkResolver().resolve(url);
    if (destination == null) {
      copyUrl(AppLocalizations.of(context).threadDetailCopyLink, url);
      return;
    }
    switch (destination.kind) {
      case YamiboForumLinkKind.thread:
        final tid = destination.tid;
        if (tid == null || tid.isEmpty) {
          copyUrl(
            AppLocalizations.of(context).threadDetailPostLink,
            destination.uri.toString(),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ThreadDetailPage(tid: tid)),
        );
        return;
      case YamiboForumLinkKind.threadPost:
        _openThreadPost(destination);
        return;
      case YamiboForumLinkKind.tagThreadPage:
        final tagId = destination.tagId;
        if (tagId == null || tagId.isEmpty) {
          copyUrl(
            AppLocalizations.of(context).threadDetailExternalLink,
            destination.uri.toString(),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                YamiboTagThreadPage(tagId: tagId, page: destination.page ?? 1),
          ),
        );
        return;
      case YamiboForumLinkKind.managedWebView:
        openManagedWebView(destination.uri);
        return;
      case YamiboForumLinkKind.external:
        copyUrl(
          AppLocalizations.of(context).threadDetailExternalLink,
          destination.uri.toString(),
        );
        return;
    }
  }

  Future<void> _openThreadPost(YamiboForumLinkDestination destination) async {
    final tid = destination.tid?.trim();
    final pid = destination.pid?.trim();
    if (tid == null || tid.isEmpty || pid == null || pid.isEmpty) {
      copyUrl(
        AppLocalizations.of(context).threadDetailFloorLink,
        destination.uri.toString(),
      );
      return;
    }
    final directPage = destination.page;
    if (directPage != null && directPage > 0) {
      _pushThreadPost(tid: tid, page: directPage, pid: pid);
      return;
    }
    final result = await ref
        .read(threadPostLocatorProvider)
        .locate(tid: tid, pid: pid, sourceUri: destination.uri);
    if (!context.mounted || !isCurrent()) {
      return;
    }
    if (result case ApiSuccess<ThreadPostLocation>(:final data)) {
      _pushThreadPost(tid: data.tid, page: data.page, pid: data.pid);
      return;
    }
    _showSnackBar(AppLocalizations.of(context).threadDetailFloorLocatorFailed);
    _pushThreadPost(tid: tid, page: 1, pid: pid);
  }

  void _pushThreadPost({
    required String tid,
    required int page,
    required String pid,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ThreadDetailPage(tid: tid, initialPage: page, targetPid: pid),
      ),
    );
  }

  void openManagedWebView(Uri uri) {
    final routeFactory = ref.read(forumWebViewRouteFactoryProvider);
    Navigator.of(context).push(
      routeFactory(
        ForumWebViewLaunchConfig(initialUri: uri, popOnRootBack: true),
      ),
    );
  }

  Future<void> copyUrl(String label, String url) async {
    final value = url.trim();
    if (value.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted || !isCurrent()) {
      return;
    }
    _showSnackBar(
      ThreadTextResolver.copySuccess(AppLocalizations.of(context), label),
    );
  }
}
