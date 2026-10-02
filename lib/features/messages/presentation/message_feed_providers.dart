import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/domain/message_repository.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';

final messageAccountIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authSessionControllerProvider).value;
  return session?.isLoggedIn == true && !session!.isLoggingOut
      ? session.uid
      : null;
});

final messageRefreshBusProvider = Provider<MessageRefreshBus>((ref) {
  final bus = MessageRefreshBus();
  ref.onDispose(bus.dispose);
  return bus;
});

/// Null target is the conversation directory; each target has its own state.
final privateMessageFeedProvider = Provider.autoDispose
    .family<
      MessageFeedController<ForumPrivateMessagePage>,
      ForumConversationTarget?
    >((ref, target) {
      final account = ref.watch(messageAccountIdProvider);
      final repository = ref.watch(messageRepositoryProvider);
      final conversation = target != null;
      var visited = false;
      final bus = ref.watch(messageRefreshBusProvider);
      late final MessageFeedController<ForumPrivateMessagePage> controller;
      controller = MessageFeedController<ForumPrivateMessagePage>(
        initialPage: conversation ? 0 : 1,
        load: (page, cancellation) async {
          if (account == null) {
            return const DataReadFailure(
              kind: DataReadFailureKind.unauthorized,
              code: 'message_login_required',
              diagnosticMessage: 'message_login_required',
            );
          }
          final result = await _loadMessages(
            repository,
            target,
            page,
            cancellation,
            controller.value.data,
          );
          final owner = result.dataOrNull?.currentUserId;
          if (owner != null && owner.isNotEmpty && owner != account) {
            return const DataReadFailure(
              kind: DataReadFailureKind.unauthorized,
              code: 'message_account_changed',
              diagnosticMessage: 'message_account_changed',
            );
          }
          if (conversation &&
              !visited &&
              !cancellation.isCancelled &&
              result.dataOrNull != null) {
            visited = true;
            bus.publish(
              MessageRefreshEvent(
                accountId: account,
                kind: MessageRefreshKind.messages,
                directoryOnly: true,
              ),
            );
          }
          return result;
        },
        nextPage: (data) => conversation
            ? (data.hasPrevious ? data.page - 1 : null)
            : (data.hasNext ? data.page + 1 : null),
        mergeMore: (current, next) =>
            _mergeMessages(current, next, older: conversation),
        mergeRefresh: conversation ? _refreshConversation : null,
      );
      final subscription = ref.watch(messageRefreshBusProvider).events.listen((
        event,
      ) {
        if (event.accountId == account &&
            event.kind == MessageRefreshKind.messages &&
            (!event.directoryOnly || target == null) &&
            (target == null ||
                event.target == null ||
                event.target == target)) {
          controller.invalidate();
        }
      });
      ref.onDispose(() {
        unawaited(subscription.cancel());
        controller.dispose();
      });
      return controller;
    });

final notificationFeedProvider =
    Provider.autoDispose<MessageFeedController<ForumNotificationPage>>((ref) {
      final account = ref.watch(messageAccountIdProvider);
      final repository = ref.watch(messageRepositoryProvider);
      final controller = MessageFeedController<ForumNotificationPage>(
        initialPage: 1,
        load: (page, cancellation) => account == null
            ? Future.value(
                const DataReadFailure(
                  kind: DataReadFailureKind.unauthorized,
                  code: 'message_login_required',
                  diagnosticMessage: 'message_login_required',
                ),
              )
            : repository.loadNotifications(
                ForumNotificationQuery(page: page, cancellation: cancellation),
              ),
        nextPage: (data) =>
            data.perPage > 0 && data.page * data.perPage < data.count
            ? data.page + 1
            : null,
        mergeMore: (current, next) => ForumNotificationPage(
          items: _unique([...current.items, ...next.items], (item) => item.id),
          count: next.count,
          page: next.page,
          perPage: next.perPage,
        ),
      );
      final subscription = ref.watch(messageRefreshBusProvider).events.listen((
        event,
      ) {
        if (event.accountId == account &&
            event.kind == MessageRefreshKind.notifications) {
          controller.invalidate();
        }
      });
      ref.onDispose(() {
        unawaited(subscription.cancel());
        controller.dispose();
      });
      return controller;
    });

ForumPrivateMessagePage _mergeMessages(
  ForumPrivateMessagePage current,
  ForumPrivateMessagePage next, {
  required bool older,
}) => ForumPrivateMessagePage(
  items: _unique(
    older
        ? [...next.items, ...current.items]
        : [...current.items, ...next.items],
    (item) => older ? item.messageId : _conversationIdentity(item),
  ),
  count: next.count,
  page: next.page,
  perPage: next.perPage,
  currentUserId: next.currentUserId,
  replyMessageId: older ? current.replyMessageId : next.replyMessageId,
);

String _conversationIdentity(ForumPrivateMessageItem item) {
  final target = item.target;
  return target == null
      ? (item.conversationId ?? item.messageId)
      : '${target.kind.name}:${target.id}';
}

// The source counts page offsets from the newest message. When the total grows
// into another page, shift the older cursor too, so loading history cannot skip
// the messages between the retained range and the next server page.
ForumPrivateMessagePage _refreshConversation(
  ForumPrivateMessagePage current,
  ForumPrivateMessagePage next,
) {
  if (next.count < current.count ||
      next.perPage != current.perPage ||
      next.perPage < 1 ||
      next.count - current.count > next.items.length) {
    // A whole unseen page between retained history and the newest window
    // cannot be represented as contiguous history. Restart at the latest page
    // so subsequent older reads traverse the gap in source order.
    return next;
  }
  final pageDelta =
      (next.count / next.perPage).ceil() -
      (current.count / current.perPage).ceil();
  final cursor = (current.page + pageDelta).clamp(1, next.page);
  return ForumPrivateMessagePage(
    items: _unique([...current.items, ...next.items], (item) => item.messageId),
    count: next.count,
    page: cursor,
    perPage: next.perPage,
    currentUserId: next.currentUserId,
    replyMessageId: next.replyMessageId,
  );
}

List<T> _unique<T>(Iterable<T> items, String Function(T) identity) =>
    List.unmodifiable({for (final item in items) identity(item): item}.values);

Future<PrivateMessageRead> _loadMessages(
  MessageRepository repository,
  ForumConversationTarget? target,
  int page,
  ForumRequestCancellation cancellation,
  ForumPrivateMessagePage? previous,
) async {
  var requestedPage = page;
  // A new message can move the page boundary while an older-page read is in
  // flight. Re-read the corrected range before merging, with a bounded retry
  // count for extremely active conversations. No command is replayed here.
  for (var attempt = 0; attempt < 3; attempt++) {
    if (cancellation.isCancelled) {
      return const DataReadFailure(
        kind: DataReadFailureKind.cancelled,
        code: 'request_cancelled',
        diagnosticMessage: 'request_cancelled',
      );
    }
    final result = await repository.loadMessages(
      target == null
          ? ForumPrivateMessageQuery(
              page: requestedPage,
              cancellation: cancellation,
            )
          : ForumPrivateMessageQuery.conversation(
              target: target,
              page: requestedPage,
              cancellation: cancellation,
            ),
    );
    final data = result.dataOrNull;
    if (target == null || page == 0 || previous == null || data == null) {
      return result;
    }
    if (data.currentUserId.isNotEmpty &&
        previous.currentUserId.isNotEmpty &&
        data.currentUserId != previous.currentUserId) {
      return result;
    }
    if (data.count < previous.count ||
        data.perPage != previous.perPage ||
        data.perPage < 1) {
      break;
    }
    final delta =
        (data.count / data.perPage).ceil() -
        (previous.count / previous.perPage).ceil();
    final correctedPage = page + delta;
    if (data.page == correctedPage) return result;
    requestedPage = correctedPage;
  }
  return const DataReadFailure(
    kind: DataReadFailureKind.business,
    code: 'message_history_changed',
    diagnosticMessage: 'message_history_changed',
  );
}
