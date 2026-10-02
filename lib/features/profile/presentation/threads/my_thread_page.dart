import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/profile/data/providers/thread_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_card.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_controller.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_pager.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/presentation/services/thread_post_route_launcher.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';
import 'package:y300/shared/widgets/forum_pull_to_refresh.dart';

typedef MyThreadOpener =
    void Function(
      BuildContext context,
      UserThreadSummary thread,
      UserThreadReplyPreview? reply,
    );

class MyThreadPage extends ConsumerStatefulWidget {
  const MyThreadPage({
    super.key,
    this.initialType = UserThreadDirectoryType.threads,
    this.isActive = true,
    this.onOpenThread,
  });

  final UserThreadDirectoryType initialType;
  final bool isActive;
  final MyThreadOpener? onOpenThread;

  @override
  ConsumerState<MyThreadPage> createState() => _MyThreadPageState();
}

class _MyThreadPageState extends ConsumerState<MyThreadPage> {
  final _postRouteSession = ThreadPostNavigationSession();

  @override
  void dispose() {
    _postRouteSession.dispose();
    super.dispose();
  }

  void _open(
    MyThreadController controller,
    VerifiedProfileOwner owner,
    UserThreadDirectoryType type,
    UserThreadSummary item,
    UserThreadReplyPreview? reply,
  ) {
    bool current() =>
        mounted &&
        widget.isActive &&
        ref.read(verifiedProfileOwnerProvider) == owner &&
        controller.value.query.type == type &&
        ModalRoute.of(context)?.isCurrent != false;
    if (!current()) return;
    if (widget.onOpenThread != null) {
      widget.onOpenThread!(context, item, reply);
      return;
    }
    if (reply == null) {
      _postRouteSession.invalidate();
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ThreadDetailPage(
              tid: item.threadId,
              subject: item.title,
              initialForumName: item.forumName,
            ),
          ),
        ),
      );
      return;
    }
    unawaited(
      launchThreadPostRoute(
        context: context,
        session: _postRouteSession,
        resolver: ref.read(threadPostRouteResolverProvider),
        target: ThreadPostTarget.fromLink(
          tid: item.threadId,
          pid: reply.postId,
          sourceUri: reply.uri,
        ),
        subject: item.title,
        isCurrent: current,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = Theme.of(context).y300NativeContent;
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final appBar = AppBar(title: Text(l10n.profileMyThreadsTitle));
    if (owner == null) {
      _postRouteSession.invalidate();
      return Scaffold(
        backgroundColor: palette.background,
        appBar: appBar,
        body: const _MyThreadLoginPrompt(),
      );
    }
    final controller = ref.watch(
      myThreadControllerProvider(
        MyThreadPageArgs(initialType: widget.initialType, routeOwner: this),
      ),
    );
    return _MyThreadReadView(
      key: ObjectKey(controller),
      controller: controller,
      isActive: widget.isActive,
      builder: (context, state) => Scaffold(
        backgroundColor: palette.background,
        appBar: appBar,
        body: MyThreadPager(
          key: ObjectKey(controller),
          selectedType: state.query.type,
          onSelected: (type) {
            _postRouteSession.invalidate();
            unawaited(controller.selectType(type));
          },
          pageBuilder: (context, type) => _MyThreadFeed(
            controller: controller,
            state: controller.stateForType(type),
            isActive: widget.isActive && state.query.type == type,
            listKey: PageStorageKey('my-threads:$owner:$type'),
            onOpen: (item, reply) =>
                _open(controller, owner, type, item, reply),
          ),
        ),
      ),
    );
  }
}

class _MyThreadReadView extends StatefulWidget {
  const _MyThreadReadView({
    super.key,
    required this.controller,
    required this.isActive,
    required this.builder,
  });

  final MyThreadController controller;
  final bool isActive;
  final Widget Function(BuildContext, MyThreadPageState) builder;

  @override
  State<_MyThreadReadView> createState() => _MyThreadReadViewState();
}

class _MyThreadReadViewState extends State<_MyThreadReadView> {
  void _sync() => unawaited(
    widget.controller.setActive(
      widget.isActive && (ModalRoute.isCurrentOf(context) ?? true),
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _MyThreadReadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    unawaited(widget.controller.setActive(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.controller,
    builder: (context, state, _) => widget.builder(context, state),
  );
}

class _MyThreadFeed extends StatefulWidget {
  const _MyThreadFeed({
    required this.controller,
    required this.state,
    required this.isActive,
    required this.listKey,
    required this.onOpen,
  });

  final MyThreadController controller;
  final MyThreadPageState state;
  final bool isActive;
  final PageStorageKey<String> listKey;
  final void Function(UserThreadSummary, UserThreadReplyPreview?) onOpen;

  @override
  State<_MyThreadFeed> createState() => _MyThreadFeedState();
}

class _MyThreadFeedState extends State<_MyThreadFeed> {
  static const _autoLoadMoreThreshold = 300.0;
  final _scrollController = ScrollController();
  bool _loadMoreCheckScheduled = false;

  // The outgoing tab may still receive a gesture during the swipe animation.
  // Its actions must stay bound to the tab it displays.
  bool get _current =>
      widget.isActive &&
      widget.controller.value.query == widget.state.query &&
      (ModalRoute.isCurrentOf(context) ?? true);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleAutoLoadMoreCheck);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      _current ? widget.controller.refresh() : Future.value();

  void _scheduleAutoLoadMoreCheck() {
    if (_loadMoreCheckScheduled) return;
    _loadMoreCheckScheduled = true;
    // Reads notify the page synchronously. Check after layout so neither a
    // scroll notification nor a short-page fill can update it during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreCheckScheduled = false;
      if (!mounted || !_current || !_scrollController.hasClients) return;
      final state = widget.controller.value;
      if (state.isBusy || state.failure != null || !state.hasMore) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions ||
          position.pixels < position.minScrollExtent ||
          position.extentAfter > _autoLoadMoreThreshold) {
        return;
      }
      unawaited(widget.controller.loadMore());
    });
    // Metrics can arrive after the frame, without another scroll or rebuild.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAutoLoadMoreCheck();
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    final controller = widget.controller;
    final isActive = widget.isActive;
    final data = state.data;
    final type = state.query.type;
    return TickerMode(
      enabled: isActive,
      child: ForumPullToRefresh(
        key: ValueKey('my-thread-refresh-${type.name}'),
        onRefresh: _refresh,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _scheduleAutoLoadMoreCheck();
            return false;
          },
          child: CustomScrollView(
            key: widget.listKey,
            controller: _scrollController,
            physics: ForumPullToRefresh.scrollPhysics,
            slivers: [
              if (data == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: !isActive
                      ? const SizedBox.shrink()
                      : state.isBusy
                      ? const Center(child: CircularProgressIndicator())
                      : _MyThreadFailure(
                          failure: state.failure,
                          onRetry: () {
                            if (_current) unawaited(controller.retry());
                          },
                        ),
                )
              else if (data.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            type == UserThreadDirectoryType.threads
                                ? Icons.article_outlined
                                : Icons.reply,
                            size: 40,
                            color: Theme.of(context).y300NativeContent.muted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            type == UserThreadDirectoryType.threads
                                ? l10n.profileNoThreads
                                : l10n.profileNoReplies,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).y300NativeContent.supportingText,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    ForumContentSpacing.pageHorizontal,
                    ForumContentSpacing.listTop,
                    ForumContentSpacing.pageHorizontal,
                    0,
                  ),
                  sliver: SliverList.separated(
                    itemCount: data.items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: ForumContentSpacing.postCardGap),
                    itemBuilder: (context, index) {
                      final item = data.items[index];
                      return MyThreadCard(
                        key: ValueKey('my-thread-${item.threadId}'),
                        item: item,
                        type: type,
                        onOpenThread: () {
                          if (_current) widget.onOpen(item, null);
                        },
                        onOpenReply: (reply) {
                          if (_current) widget.onOpen(item, reply);
                        },
                      );
                    },
                  ),
                ),
              if (data != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: state.failure != null
                        ? _MyThreadFailure(
                            failure: state.failure,
                            onRetry: () {
                              if (_current) unawaited(controller.retry());
                            },
                          )
                        : state.operation == MyThreadReadOperation.more
                        ? const Center(child: CircularProgressIndicator())
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyThreadFailure extends StatelessWidget {
  const _MyThreadFailure({required this.failure, required this.onRetry});

  final DataReadFailure<
    UserThreadDirectoryData,
    UserThreadDirectoryReadCapabilities
  >?
  failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (failure?.kind == DataReadFailureKind.unauthorized) {
      return const _MyThreadLoginPrompt();
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).y300NativeContent.accent,
              size: 34,
            ),
            const SizedBox(height: 12),
            Text(
              failure == null
                  ? l10n.profileThreadsReadFailed
                  : LocalizedErrorSummary.resolve(l10n, failure),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('my-thread-retry'),
              onPressed: onRetry,
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyThreadLoginPrompt extends StatelessWidget {
  const _MyThreadLoginPrompt();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.profileThreadsLoginRequired, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ),
              child: Text(l10n.authLoginTitle),
            ),
          ],
        ),
      ),
    );
  }
}
