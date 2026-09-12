import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';
import 'package:y300/features/messages/presentation/widgets/message_feed_view.dart';
import 'package:y300/features/messages/presentation/widgets/message_read_status.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Shared list chrome; private messages and notifications keep separate state.
class MessageFeedList<P> extends StatelessWidget {
  const MessageFeedList({
    super.key,
    required this.controller,
    required this.isActive,
    required this.listKey,
    required this.itemCount,
    required this.itemBuilder,
    required this.emptyText,
    required this.emptyIcon,
  });
  final MessageFeedController<P> controller;
  final bool isActive;
  final PageStorageKey<String> listKey;
  final int Function(P) itemCount;
  final Widget Function(BuildContext, P, int) itemBuilder;
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
        if (data == null) {
          return Center(
            child: SingleChildScrollView(
              child: MessageReadStatus(
                failure: state.failure,
                onRetry: controller.refresh,
              ),
            ),
          );
        }
        final count = itemCount(data);
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: CustomScrollView(
            key: listKey,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (state.operation == MessageFeedOperation.refresh)
                SliverToBoxAdapter(
                  child: LinearProgressIndicator(
                    color: Theme.of(context).y300NativeContent.accent,
                    value: MediaQuery.disableAnimationsOf(context) ? 0.5 : null,
                  ),
                ),
              if (count == 0)
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
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  sliver: SliverList.separated(
                    itemCount: count,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        itemBuilder(context, data, index),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: state.failure != null
                      ? MessageReadStatus(
                          failure: state.failure,
                          onRetry:
                              state.failedOperation == MessageFeedOperation.more
                              ? controller.loadMore
                              : controller.refresh,
                        )
                      : state.operation == MessageFeedOperation.more
                      ? Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(context).y300NativeContent.accent,
                          ),
                        )
                      : controller.hasMore
                      ? Center(
                          child: TextButton(
                            onPressed: state.isBusy
                                ? null
                                : controller.loadMore,
                            child: Text(
                              AppLocalizations.of(context).messageLoadMore,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
