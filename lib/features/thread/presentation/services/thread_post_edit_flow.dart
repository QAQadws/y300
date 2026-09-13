import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/composer_shared/presentation/services/read_access_feedback.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/data/providers/post_edit_providers.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_page.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';
import 'package:y300/features/thread/presentation/post_edit_native_entry_gate.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/l10n/app_localizations.dart';

class ThreadPostEditFlow {
  const ThreadPostEditFlow({
    required this.context,
    required this.ref,
    required this.isCurrent,
    required this.onMutation,
  });
  final BuildContext context;
  final WidgetRef ref;
  final bool Function() isCurrent;
  final Future<void> Function() onMutation;
  Future<void> open(PostEditTarget target) async {
    final nativeEnabled = ref.read(postEditNativeEntryGateProvider);
    if (!nativeEnabled) {
      final routeResult = await _openPostEditFallback(target);
      if (routeResult?.serverMutationPossible == true) {
        await onMutation();
      }
      return;
    }

    ThreadPostEditPreparation? preparation;
    try {
      // Opening an editor is an explicit freshness boundary. Do not rely on
      // auto-dispose timing when the same post is reopened quickly.
      ref.invalidate(postEditPreparationProvider(target));
      final result = await ref.read(postEditPreparationProvider(target).future);
      if (result case DataReadSuccess<
        ThreadPostEditPreparation,
        ThreadPostEditCapabilities
      >(
        :final data,
      )) {
        preparation = data;
      }
    } catch (_) {
      // A failed preparation remains safely recoverable through WebView.
    }
    if (!context.mounted || !isCurrent()) {
      return;
    }
    if (preparation == null) {
      final routeResult = await _openPostEditFallback(target);
      if (routeResult?.serverMutationPossible == true) {
        await onMutation();
      }
      return;
    }

    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => PostEditComposerPage(
          args: PostEditComposerArgs(target: target, preparation: preparation!),
        ),
      ),
    );
    if (result is PostEditRouteResult && result.serverMutationPossible) {
      if (context.mounted && isCurrent()) {
        final feedback = readAccessFeedback(
          AppLocalizations.of(context),
          result.readAccess,
        );
        if (feedback != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(feedback)));
        }
      }
      await onMutation();
    }
  }

  Future<ForumWebViewRouteResult?> _openPostEditFallback(
    PostEditTarget target,
  ) async {
    final routeFactory = ref.read(forumWebViewRouteFactoryProvider);
    final result = await Navigator.of(context).push<Object?>(
      routeFactory(
        ForumWebViewLaunchConfig(
          initialUri: target.editUri,
          popOnRootBack: true,
          purpose: ForumWebViewHostPurpose.postEditFallback,
          completionTarget: ForumWebViewCompletionTarget(
            tid: target.tid,
            pid: target.pid,
          ),
        ),
      ),
    );
    return result is ForumWebViewRouteResult ? result : null;
  }
}
