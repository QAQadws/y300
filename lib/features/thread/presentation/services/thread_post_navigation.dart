import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/forum_link_opener.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_reader_exit_result.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_plain_text_extractor.dart';
import 'package:y300/features/thread/domain/services/thread_floor_link_builder.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
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
    required this.routeSession,
  });
  final BuildContext context;
  final WidgetRef ref;
  final String tid;
  final String? imageReferer;
  final bool Function() isCurrent;
  final ThreadPostNavigationSession routeSession;
  bool get mounted => context.mounted && isCurrent();
  ThreadFloorLinkBuilder get _floorLinkBuilder => ThreadFloorLinkBuilder();
  void _showSnackBar(String text) {
    if (context.mounted && isCurrent()) showTransientSnackBar(context, text);
  }

  void openImages(
    ThreadPost post,
    ThreadImageOpenRequest request, {
    Future<void> Function(ThreadImageReaderExitResult)? onBeforeExit,
  }) {
    if (request.continuousImages.isEmpty) {
      copyUrl(
        '${post.number}# ${AppLocalizations.of(context).threadDetailImageLink}',
        request.initialEntry?.url ?? '',
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<ThreadImageReaderExitResult>(
        builder: (_) => ThreadImageReaderPage(
          request: request,
          imageReferer: imageReferer,
          onBeforeExit: onBeforeExit,
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

  Future<void> copyPlainText(ThreadPost post, String displayedHtml) {
    final text = const ThreadPostBodyPlainTextExtractor().extractHtml(
      displayedHtml,
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
    _openProfile(post.authorId.trim());
  }

  void openCommentAuthor(ThreadPostCommentEntry comment) {
    final uid = _commentAuthorUid(comment);
    _openProfile(uid);
  }

  void _openProfile(String? uid) {
    if (!mounted) return;
    if (uid == null || !RegExp(r'^[1-9]\d*$').hasMatch(uid)) {
      _showSnackBar(AppLocalizations.of(context).threadDetailUidMissing);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => UserProfilePage(uid: uid)),
    );
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

  void openLink(String url) {
    unawaited(_openLink(url, isCurrent));
  }

  Future<void> openSelectedLink(
    String url,
    bool Function() selectionIsCurrent,
  ) => _openLink(url, () => isCurrent() && selectionIsCurrent());

  Future<void> _openLink(String url, bool Function() current) async {
    if (!context.mounted || !current()) return;
    await ref
        .read(forumLinkOpenerProvider)
        .open(
          context: context,
          url: url,
          session: routeSession,
          isCurrent: current,
          onCopyLink: (value) =>
              copyUrl(AppLocalizations.of(context).threadDetailCopyLink, value),
        );
  }

  Future<void> copyUrl(String label, String url) async {
    final value = url.trim();
    if (value.isEmpty) {
      return;
    }
    await ref.read(clipboardTextWriterProvider).writeText(value);
    if (!context.mounted || !isCurrent()) {
      return;
    }
    _showSnackBar(
      ThreadTextResolver.copySuccess(AppLocalizations.of(context), label),
    );
  }
}
