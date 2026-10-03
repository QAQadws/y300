import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Failed entry returns to its source. Feedback uses only the snackbar, including
/// when a root route has no source or access is revoked after reading.
class BlogDetailFailureFeedback extends ConsumerStatefulWidget {
  const BlogDetailFailureFeedback({
    super.key,
    required this.controller,
    required this.child,
  });

  final ProfileBlogDetailController controller;
  final Widget child;

  @override
  ConsumerState<BlogDetailFailureFeedback> createState() =>
      _BlogDetailFailureFeedbackState();
}

class _BlogDetailFailureFeedbackState
    extends ConsumerState<BlogDetailFailureFeedback> {
  bool _active = true;
  bool _hasContent = false;
  UserBlogDetailPageState? _reportedFailure;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onReadChanged);
  }

  @override
  void didUpdateWidget(covariant BlogDetailFailureFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_onReadChanged);
      widget.controller.addListener(_onReadChanged);
      _hasContent = false;
      _reportedFailure = null;
    }
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onReadChanged);
    super.dispose();
  }

  void _onReadChanged() {
    if (!mounted || !_active) return;
    final controller = widget.controller;
    final state = controller.value;
    if (state.data != null) {
      _hasContent = true;
      return;
    }
    if (identical(_reportedFailure, state) ||
        state.isLoading ||
        state.failure == null ||
        state.failure!.kind == DataReadFailureKind.cancelled) {
      return;
    }
    final accountOwner = ref.read(blogMutationBusProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_active ||
          identical(_reportedFailure, state) ||
          !identical(widget.controller, controller) ||
          !identical(controller.value, state) ||
          !identical(ref.read(blogMutationBusProvider), accountOwner) ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final navigator = Navigator.of(context);
      _reportedFailure = state;
      final l10n = AppLocalizations.of(context);
      final uri = ref.read(userBlogNavigationProvider)?.detail(state.query);
      final factory = ref.read(forumWebViewRouteFactoryProvider);
      final actor = ref.read(blogAccountIdProvider);
      final message = ProfileTextResolver.blogReadError(l10n, state.failure);
      // The action outlives this page. Use the surviving navigator context,
      // never this State/WidgetRef, and reject a changed account generation.
      if (!_hasContent && navigator.canPop()) navigator.pop();
      showTransientSnackBar(
        navigator.context,
        message,
        snackBarKey: const Key('blog-detail-failure-snackbar'),
        actionOverflowThreshold: 0.5,
        action: uri == null
            ? null
            : SnackBarAction(
                key: const Key('blog-read-open-web'),
                label: l10n.profileBlogOpenWeb,
                onPressed: () {
                  if (!navigator.mounted) return;
                  final container = ProviderScope.containerOf(
                    navigator.context,
                    listen: false,
                  );
                  if (!identical(
                    container.read(blogMutationBusProvider),
                    accountOwner,
                  )) {
                    return;
                  }
                  unawaited(
                    navigator.push(
                      factory(
                        ForumWebViewLaunchConfig(
                          initialUri: uri,
                          popOnRootBack: true,
                          navigationPolicy:
                              ForumWebViewNavigationPolicy.keepWebView,
                          expectedAccountId: actor,
                        ),
                      ),
                    ),
                  );
                },
              ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Also handles a failure that arrived while this route was covered.
    ModalRoute.isCurrentOf(context);
    _onReadChanged();
    return widget.child;
  }
}
