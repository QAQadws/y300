import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/providers/friend_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_view.dart';
import 'package:y300/features/profile/presentation/friends/friend_action_sheet.dart';
import 'package:y300/features/profile/presentation/friends/friend_list_row.dart';
import 'package:y300/features/profile/presentation/friends/friend_read_status.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_controller.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_scope_pager.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/forum_pull_to_refresh.dart';
import 'package:y300/shared/widgets/native_pagination_bar.dart';

typedef FriendUserOpener = void Function(BuildContext context, String userId);
typedef FriendConversationOpener =
    void Function(
      BuildContext context,
      ForumConversationTarget target,
      String title,
    );

class MyFriendsPage extends ConsumerStatefulWidget {
  const MyFriendsPage({
    super.key,
    required this.onOpenUser,
    required this.onOpenConversation,
    this.isActive = true,
    this.initialScope = ForumFriendFeedScope.friends,
    this.initialPage = 1,
  }) : assert(initialPage >= 1);

  final FriendUserOpener onOpenUser;
  final FriendConversationOpener onOpenConversation;
  final bool isActive;
  final ForumFriendFeedScope initialScope;
  final int initialPage;

  @override
  ConsumerState<MyFriendsPage> createState() => _MyFriendsPageState();
}

class _MyFriendsPageState extends ConsumerState<MyFriendsPage> {
  bool _openingActions = false;

  MyFriendsPageArgs get _args => MyFriendsPageArgs(
    routeOwner: this,
    initialScope: widget.initialScope,
    initialPage: widget.initialPage,
  );

  bool _ownsController(MyFriendsController controller) =>
      mounted &&
      widget.isActive &&
      controller.isCurrentOwner &&
      ref.read(verifiedProfileOwnerProvider) == controller.owner &&
      identical(ref.read(myFriendsControllerProvider(_args)), controller);

  bool _current(
    MyFriendsController controller, [
    ForumFriendFeedScope? scope,
  ]) =>
      _ownsController(controller) &&
      (ModalRoute.isCurrentOf(context) ?? true) &&
      (scope == null || controller.value.query.scope == scope);

  ForumFriendFeedItem? _boundItem(
    MyFriendsController controller,
    FriendActionTarget target, {
    bool requireCurrentRoute = true,
  }) {
    if (!_ownsController(controller) || controller.owner != target.owner) {
      return null;
    }
    final route = ModalRoute.of(context);
    if (route?.isActive == false ||
        (requireCurrentRoute && route?.isCurrent == false)) {
      return null;
    }
    final state = controller.value;
    if (state.query.scope != target.scope || state.currentPage != target.page) {
      return null;
    }
    for (final item in state.data?.items ?? const <ForumFriendFeedItem>[]) {
      if (item.userId == target.userId &&
          RegExp(r'^[1-9]\d*$').hasMatch(item.userId)) {
        return item;
      }
    }
    return null;
  }

  void _openMessage(MyFriendsController controller, FriendActionTarget target) {
    final item = _boundItem(controller, target);
    if (item == null) return;
    widget.onOpenConversation(
      context,
      ForumConversationTarget.direct(item.userId),
      item.username,
    );
  }

  Future<void> _showActions(
    MyFriendsController controller,
    FriendActionTarget target,
  ) async {
    if (_openingActions || _boundItem(controller, target) == null) return;
    _openingActions = true;
    try {
      final action = await showModalBottomSheet<FriendAction>(
        context: context,
        builder: (_) => FriendActionSheet(
          target: target,
          controller: controller,
          // Covering the originating route is expected while its sheet is open.
          isTargetAttached: () =>
              _boundItem(controller, target, requireCurrentRoute: false) !=
              null,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _boundItem(controller, target) == null) return;
      switch (action) {
        case FriendAction.message:
          _openMessage(controller, target);
        case FriendAction.remove:
          await _removeFriend(controller, target);
        case null:
          return;
      }
    } finally {
      _openingActions = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = Theme.of(context).y300NativeContent;
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final appBar = AppBar(title: Text(l10n.profileMyFriendsTitle));
    if (owner == null) {
      return Scaffold(
        key: const Key('my-friends-page'),
        backgroundColor: palette.background,
        appBar: appBar,
        body: const FriendLoginPrompt(),
      );
    }
    final controller = ref.watch(myFriendsControllerProvider(_args));
    final referer = ref.watch(forumImageRefererProvider);
    return BlogReadView<MyFriendsPageState>(
      key: ObjectKey(controller),
      listenable: controller,
      setActive: controller.setActive,
      isActive: widget.isActive,
      builder: (context, state, _) => Scaffold(
        key: const Key('my-friends-page'),
        backgroundColor: palette.background,
        appBar: appBar,
        body: MyFriendsScopePager(
          key: ObjectKey(controller),
          selectedScope: state.query.scope,
          onSelected: (scope) {
            if (_current(controller)) {
              unawaited(controller.selectScope(scope));
            }
          },
          pageBuilder: (context, scope) {
            final scopeState = controller.stateForScope(scope);
            FriendActionTarget target(ForumFriendFeedItem item) =>
                FriendActionTarget(
                  owner: owner,
                  scope: scope,
                  page: scopeState.currentPage,
                  userId: item.userId,
                );
            return _FriendsFeed(
              controller: controller,
              state: scopeState,
              imageReferer: referer,
              isActive: widget.isActive && state.query.scope == scope,
              listKey: PageStorageKey('my-friends-list-${scope.name}:$owner'),
              onOpenUser: (item) {
                final current = _boundItem(controller, target(item));
                if (current != null) {
                  widget.onOpenUser(context, current.userId);
                }
              },
              onMessage: (item) => _openMessage(controller, target(item)),
              onShowActions: (item) => _showActions(controller, target(item)),
            );
          },
        ),
      ),
    );
  }

  Future<void> _removeFriend(
    MyFriendsController controller,
    FriendActionTarget target,
  ) async {
    final item = _boundItem(controller, target);
    if (item == null ||
        target.scope != ForumFriendFeedScope.friends ||
        !item.canRemove ||
        controller.value.isLoading ||
        controller.value.isRemoving ||
        controller.value.unverifiedRemovalUserIds.contains(item.userId)) {
      return;
    }
    final owner = controller.owner;
    if (owner == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _RemoveFriendDialog(owner: owner, username: item.username),
    );
    // The dialog route must be removed before active-route ownership resumes.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || confirmed != true) return;
    final current = _boundItem(controller, target);
    if (current == null ||
        !current.canRemove ||
        controller.value.isLoading ||
        controller.value.isRemoving ||
        controller.value.unverifiedRemovalUserIds.contains(current.userId)) {
      return;
    }
    final result = await controller.removeFriend(current.userId);
    if (!mounted) return;
    if (!_current(controller)) return;
    if (result is DataCommandOutcomeUnknown<ForumFriendRemovalReceipt>) return;
    final l10n = AppLocalizations.of(context);
    final message = result is DataCommandApplied<ForumFriendRemovalReceipt>
        ? l10n.profileFriendRemoved
        : LocalizedErrorSummary.resolve(l10n, result);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FriendsFeed extends StatelessWidget {
  const _FriendsFeed({
    required this.controller,
    required this.state,
    required this.imageReferer,
    required this.isActive,
    required this.listKey,
    required this.onOpenUser,
    required this.onMessage,
    required this.onShowActions,
  });

  final MyFriendsController controller;
  final MyFriendsPageState state;
  final String imageReferer;
  final bool isActive;
  final PageStorageKey<String> listKey;
  final ValueChanged<ForumFriendFeedItem> onOpenUser;
  final ValueChanged<ForumFriendFeedItem> onMessage;
  final ValueChanged<ForumFriendFeedItem> onShowActions;

  // Outgoing tabs can receive gestures while a swipe is still animating.
  bool _current(BuildContext context) =>
      isActive &&
      controller.isCurrentOwner &&
      controller.value.query.scope == state.query.scope &&
      controller.value.currentPage == state.currentPage &&
      (ModalRoute.isCurrentOf(context) ?? true);

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    final scope = state.query.scope;
    final l10n = AppLocalizations.of(context);
    return TickerMode(
      enabled: isActive,
      child: Column(
        children: [
          if (data != null &&
              scope == ForumFriendFeedScope.friends &&
              data.items.any(
                (item) => state.unverifiedRemovalUserIds.contains(item.userId),
              ))
            FriendRemovalVerification(
              key: const Key('my-friends-removal-verification'),
              isBusy: state.isLoading || state.isRemoving,
              onVerify: () {
                if (_current(context)) unawaited(controller.refresh());
              },
            ),
          Expanded(
            child: ForumPullToRefresh(
              onRefresh: () =>
                  _current(context) ? controller.refresh() : Future.value(),
              child: CustomScrollView(
                key: listKey,
                physics: ForumPullToRefresh.scrollPhysics,
                slivers: [
                  if (data == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: !isActive
                          ? const SizedBox.shrink()
                          : state.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Center(
                              child: FriendReadFailure(
                                failure: state.failure,
                                onRetry: () {
                                  if (_current(context)) {
                                    unawaited(controller.refresh());
                                  }
                                },
                              ),
                            ),
                    )
                  else if (data.items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: FriendEmptyState(scope: scope)),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      sliver: SliverList.separated(
                        itemCount: data.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = data.items[index];
                          final hasIdentity = RegExp(
                            r'^[1-9]\d*$',
                          ).hasMatch(item.userId);
                          return FriendListRow(
                            key: Key(
                              hasIdentity
                                  ? 'my-friends-user-${item.userId}'
                                  : 'my-friends-anonymous-$index',
                            ),
                            item: item,
                            imageReferer: imageReferer,
                            onOpenUser: hasIdentity
                                ? () {
                                    if (_current(context)) onOpenUser(item);
                                  }
                                : null,
                            onMessage: hasIdentity
                                ? () {
                                    if (_current(context)) onMessage(item);
                                  }
                                : null,
                            onShowActions: hasIdentity
                                ? () {
                                    if (_current(context)) onShowActions(item);
                                  }
                                : null,
                          );
                        },
                      ),
                    ),
                  if (data != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            if (state.failure != null)
                              FriendReadFailure(
                                failure: state.failure,
                                onRetry: () {
                                  if (_current(context)) {
                                    unawaited(controller.refresh());
                                  }
                                },
                              ),
                            NativePaginationBar(
                              currentPage: state.currentPage,
                              lastPage: state.lastPage,
                              hasMore: state.canLoadNext,
                              canLoadPrevious: state.canLoadPrevious,
                              isLoading: state.isLoading || state.isRemoving,
                              onLoadPrevious: () {
                                if (_current(context)) {
                                  unawaited(controller.loadPreviousPage());
                                }
                              },
                              onLoadNext: () {
                                if (_current(context)) {
                                  unawaited(controller.loadNextPage());
                                }
                              },
                              onSelectPage: (page) async {
                                await WidgetsBinding.instance.endOfFrame;
                                if (!context.mounted || !_current(context)) {
                                  return;
                                }
                                await controller.loadPageNumber(page);
                              },
                              previousLabel: l10n.commonPreviousPage,
                              currentLabel: state.lastPage == null
                                  ? l10n.commonPage(state.currentPage)
                                  : l10n.commonPageOf(
                                      state.currentPage,
                                      state.lastPage!,
                                    ),
                              nextLabel: l10n.commonNextPage,
                              previousButtonKey: const Key(
                                'my-friends-page-previous',
                              ),
                              currentPageButtonKey: const Key(
                                'my-friends-page-current',
                              ),
                              nextButtonKey: const Key('my-friends-page-next'),
                              menuKeyPrefix: 'my-friends-page',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoveFriendDialog extends ConsumerStatefulWidget {
  const _RemoveFriendDialog({required this.owner, required this.username});

  final VerifiedProfileOwner owner;
  final String username;

  @override
  ConsumerState<_RemoveFriendDialog> createState() =>
      _RemoveFriendDialogState();
}

class _RemoveFriendDialogState extends ConsumerState<_RemoveFriendDialog> {
  bool _dismissScheduled = false;

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    if (owner != widget.owner) {
      if ((ModalRoute.isCurrentOf(context) ?? false) && !_dismissScheduled) {
        _dismissScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _dismissScheduled = false;
          if (mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
            Navigator.of(context).pop(false);
          }
        });
      }
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.profileFriendRemoveTitle),
      content: Text(l10n.profileFriendRemoveBody(widget.username)),
      actions: [
        TextButton(
          key: const Key('my-friends-remove-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('my-friends-remove-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.profileFriendRemove),
        ),
      ],
    );
  }
}
