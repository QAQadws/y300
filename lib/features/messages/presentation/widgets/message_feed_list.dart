import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';
import 'package:y300/features/messages/presentation/widgets/message_feed_view.dart';
import 'package:y300/features/messages/presentation/widgets/message_read_status.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/delayed_loading_status.dart';
import 'package:y300/shared/widgets/navigation/navigation_dock_insets.dart';

/// Shared list chrome; private messages and notifications keep separate state.
class MessageFeedList<P> extends StatelessWidget {
  const MessageFeedList({
    super.key,
    required this.controller,
    required this.isActive,
    required this.listKey,
    required this.itemCount,
    required this.itemBuilder,
    required this.loadingText,
    required this.emptyText,
    required this.emptyIcon,
  });
  final MessageFeedController<P> controller;
  final bool isActive;
  final PageStorageKey<String> listKey;
  final int Function(P) itemCount;
  final Widget Function(BuildContext, P, int) itemBuilder;
  final String loadingText;
  final String emptyText;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: isActive,
    child: MessageFeedView<P>(
      controller: controller,
      isActive: isActive,
      builder: (context, state) {
        final data = state.data;
        final count = data == null ? 0 : itemCount(data);
        final dockPadding = EdgeInsets.only(
          bottom: NavigationDockInsets.bottomOf(context),
        );
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: CustomScrollView(
            key: listKey,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (data == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: dockPadding,
                    child: state.failure != null
                        ? Center(
                            child: MessageReadStatus(
                              failure: state.failure,
                              onRetry: controller.refresh,
                            ),
                          )
                        : isActive
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: DelayedLoadingStatus(label: loadingText),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                )
              else if (count == 0)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            emptyIcon,
                            size: 40,
                            color: Theme.of(context).y300NativeContent.muted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            emptyText,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .y300NativeContent
                                      .supportingText,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  sliver: SliverList.separated(
                    itemCount: count,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        itemBuilder(context, data, index),
                  ),
                ),
              if (data != null)
                SliverToBoxAdapter(
                  child: Padding(
                    key: const Key('message-feed-footer'),
                    padding: const EdgeInsets.all(12).add(dockPadding),
                    child: controller.hasMore || state.failure != null
                        ? _buildPageAction(context, state)
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _buildPageAction(BuildContext context, MessageFeedState<P> state) {
    final l10n = AppLocalizations.of(context);
    final loadLabel = Text(l10n.messageLoadMore);
    final failure = state.failure;
    final retryRefresh = state.failedOperation == MessageFeedOperation.refresh;
    final Widget label;
    if (failure != null) {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              LocalizedErrorSummary.resolve(l10n, failure),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(l10n.commonRetry),
        ],
      );
    } else if (isActive && state.operation == MessageFeedOperation.more) {
      label = DelayedLoadingStatus(
        key: const Key('message-feed-page-status'),
        label: l10n.messageLoadingMore,
        beforeDelay: loadLabel,
      );
    } else {
      label = loadLabel;
    }
    // The text button keeps the footer's control height across read and retry.
    return Center(
      child: TextButton(
        onPressed: state.isBusy
            ? null
            : retryRefresh
            ? controller.refresh
            : controller.loadMore,
        child: label,
      ),
    );
  }
}
