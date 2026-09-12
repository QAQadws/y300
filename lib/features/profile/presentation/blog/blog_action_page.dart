import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_action_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_web_navigation.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

const blogManagementActions = {
  UserBlogAction.delete,
  UserBlogAction.pin,
  UserBlogAction.unpin,
};

String blogActionLabel(AppLocalizations l10n, UserBlogAction action) =>
    switch (action) {
      UserBlogAction.create => l10n.profileBlogWrite,
      UserBlogAction.edit => l10n.profileBlogEdit,
      UserBlogAction.delete => l10n.profileBlogDelete,
      UserBlogAction.pin => l10n.profileBlogPin,
      UserBlogAction.unpin => l10n.profileBlogUnpin,
    };

Future<UserBlogReceipt?> openBlogActionPage(
  BuildContext context,
  WidgetRef ref, {
  required String ownerUserId,
  required String blogId,
  required UserBlogAction action,
}) async {
  final actor = ref.read(blogAccountIdProvider);
  if (actor == null) {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const LoginPage()));
    return null;
  }
  return Navigator.of(context).push<UserBlogReceipt>(
    MaterialPageRoute(
      builder: (_) => BlogActionPage(
        target: UserBlogTarget(
          actorUserId: actor,
          ownerUserId: ownerUserId,
          blogId: blogId,
          action: action,
        ),
      ),
    ),
  );
}

class BlogActionMenu extends StatelessWidget {
  const BlogActionMenu({
    super.key,
    required this.actions,
    required this.onSelected,
  });
  final Set<UserBlogAction> actions;
  final ValueChanged<UserBlogAction> onSelected;

  @override
  Widget build(BuildContext context) {
    if (!actions.any(blogManagementActions.contains)) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<UserBlogAction>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final action in blogManagementActions)
          if (actions.contains(action))
            PopupMenuItem(
              value: action,
              child: Text(
                blogActionLabel(AppLocalizations.of(context), action),
              ),
            ),
      ],
    );
  }
}

/// A prepared confirmation, separate from the article and editable body.
class BlogActionPage extends ConsumerStatefulWidget {
  const BlogActionPage({super.key, required this.target});
  final UserBlogTarget target;
  @override
  ConsumerState<BlogActionPage> createState() => _BlogActionPageState();
}

class _BlogActionPageState extends ConsumerState<BlogActionPage> {
  late final BlogActionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BlogActionController(
      target: widget.target,
      service: ref.read(userBlogOperationsProvider),
      currentActor: () => ref.read(blogAccountIdProvider),
    );
    ref.listenManual(blogAccountIdProvider, (_, actor) {
      if (actor != widget.target.actorUserId) _controller.expire();
    });
    unawaited(_controller.prepare());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final receipt = await _controller.submit();
    if (!mounted ||
        receipt == null ||
        ref.read(blogAccountIdProvider) != receipt.target.actorUserId) {
      return;
    }
    ref.read(blogMutationBusProvider).publish(receipt);
    Navigator.of(context).pop(receipt);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final native = Theme.of(context).y300NativeContent;
    final description = switch (widget.target.action) {
      UserBlogAction.delete => l10n.profileBlogDeleteBody,
      UserBlogAction.pin => l10n.profileBlogPinBody,
      UserBlogAction.unpin => l10n.profileBlogUnpinBody,
      _ => l10n.commonRequestError,
    };
    return Scaffold(
      backgroundColor: native.background,
      appBar: AppBar(title: Text(blogActionLabel(l10n, widget.target.action))),
      body: SafeArea(
        child: ValueListenableBuilder<BlogActionState>(
          valueListenable: _controller,
          builder: (context, state, _) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                state.phase == BlogActionPhase.expired
                    ? l10n.forumWebViewAccountChanged
                    : description,
                style: TextStyle(color: native.body),
              ),
              if (state.busy) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.phase == BlogActionPhase.preparing
                        ? l10n.profileBlogPreparingAction
                        : l10n.profileBlogSubmittingAction,
                    style: TextStyle(color: native.supportingText),
                  ),
                ),
                if (!MediaQuery.disableAnimationsOf(context)) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
              ],
              if (state.phase == BlogActionPhase.unknown ||
                  state.failure != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.phase == BlogActionPhase.unknown
                        ? l10n.profileBlogActionOutcomeUnknown
                        : LocalizedErrorSummary.resolve(l10n, state.failure),
                    style: TextStyle(color: native.body),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                  if (state.phase == BlogActionPhase.failed) ...[
                    TextButton(
                      key: const Key('blog-action-open-web'),
                      onPressed: () => openBlogWebPage(
                        context,
                        ref,
                        expectedActor: widget.target.actorUserId,
                        replaceCurrent: true,
                        destination: (navigation) => navigation.detail(
                          UserBlogDetailQuery(
                            ownerUserId: widget.target.ownerUserId,
                            blogId: widget.target.blogId!,
                          ),
                        ),
                      ),
                      child: Text(l10n.profileBlogOpenWeb),
                    ),
                    FilledButton(
                      key: const Key('blog-action-retry'),
                      onPressed: _controller.prepare,
                      child: Text(l10n.commonRetry),
                    ),
                  ] else if (state.phase != BlogActionPhase.expired &&
                      state.phase != BlogActionPhase.unknown)
                    FilledButton(
                      key: const Key('blog-action-submit'),
                      onPressed: state.phase == BlogActionPhase.ready
                          ? _submit
                          : null,
                      child: Text(blogActionLabel(l10n, widget.target.action)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
