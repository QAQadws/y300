import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/new_private_message_page.dart';
import 'package:y300/features/messages/presentation/notification_ignore_dialog.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/messages/presentation/widgets/message_avatar.dart';
import 'package:y300/features/messages/presentation/widgets/message_feed_list.dart';
import 'package:y300/features/messages/presentation/widgets/message_preview_text.dart';
import 'package:y300/features/messages/presentation/widgets/message_read_status.dart';
import 'package:y300/features/messages/presentation/widgets/message_surface.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_settings_sheet.dart';
import 'package:y300/l10n/app_localizations.dart';

enum MessageCenterTab { messages, notifications }

typedef MessageConversationOpener =
    void Function(
      BuildContext context,
      ForumConversationTarget target,
      String title,
    );

typedef MessageUserOpener = void Function(BuildContext context, String userId);

class MessageCenterPage extends ConsumerWidget {
  const MessageCenterPage({
    super.key,
    required this.onOpenConversation,
    required this.onOpenLink,
    required this.onOpenUser,
    this.isActive = true,
    this.initialTab = MessageCenterTab.messages,
  });
  final MessageConversationOpener onOpenConversation;
  final MessageLinkOpener onOpenLink;
  final MessageUserOpener onOpenUser;
  final bool isActive;
  final MessageCenterTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(messageAccountIdProvider);
    if (account == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).y300NativeContent.background,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).profileMessageCenterTitle),
        ),
        body: const MessageLoginPrompt(),
      );
    }
    return _MessageCenterBody(
      key: ValueKey(account),
      accountId: account,
      config: this,
    );
  }
}

class _MessageCenterBody extends ConsumerStatefulWidget {
  const _MessageCenterBody({
    super.key,
    required this.accountId,
    required this.config,
  });
  final String accountId;
  final MessageCenterPage config;

  @override
  ConsumerState<_MessageCenterBody> createState() => _MessageCenterBodyState();
}

class _MessageCenterBodyState extends ConsumerState<_MessageCenterBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _visited = <int>{};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      initialIndex: widget.config.initialTab.index,
      vsync: this,
    );
    _visited.add(_tabs.index);
    _tabs.addListener(_selectTab);
  }

  void _selectTab() => setState(() => _visited.add(_tabs.index));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final messages = ref.watch(privateMessageFeedProvider(null));
    final notifications = ref.watch(notificationFeedProvider);
    final theme = Theme.of(context);
    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).y300NativeContent.background,
      appBar: AppBar(
        title: Text(l10n.profileMessageCenterTitle),
        actions: [
          IconButton(
            tooltip: l10n.messageNew,
            icon: const Icon(Icons.edit_square),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NewPrivateMessagePage(),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.messageRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                _tabs.index == 0 ? messages.refresh() : notifications.refresh(),
          ),
          IconButton(
            tooltip: l10n.threadHtmlConversionSettings,
            icon: const Icon(Icons.text_fields),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const ForumHtmlReaderSettingsSheet(
                showConversionControls: true,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: appBarForeground,
          unselectedLabelColor: appBarForeground.withValues(alpha: 0.72),
          indicatorColor: appBarForeground,
          automaticIndicatorColorAdjustment: false,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: l10n.messageMessagesTab),
            Tab(text: l10n.messageNotificationsTab),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabs.index,
        children: [
          if (_visited.contains(0))
            MessageFeedList<ForumPrivateMessagePage>(
              controller: messages,
              isActive: widget.config.isActive && _tabs.index == 0,
              listKey: PageStorageKey(
                'private-message-list:${widget.accountId}',
              ),
              itemCount: (page) => page.items.length,
              emptyText: l10n.profileNoMessages,
              emptyIcon: Icons.chat_bubble_outline,
              itemBuilder: (context, page, index) => _ConversationRow(
                key: ValueKey(
                  page.items[index].target ?? page.items[index].messageId,
                ),
                item: page.items[index],
                accountId: widget.accountId,
                onOpen: widget.config.onOpenConversation,
              ),
            )
          else
            const SizedBox.shrink(),
          if (_visited.contains(1))
            MessageFeedList<ForumNotificationPage>(
              controller: notifications,
              isActive: widget.config.isActive && _tabs.index == 1,
              listKey: PageStorageKey('notification-list:${widget.accountId}'),
              itemCount: (page) => page.items.length,
              emptyText: l10n.profileNoNotifications,
              emptyIcon: Icons.notifications_none,
              itemBuilder: (context, page, index) => _NotificationRow(
                key: ValueKey(page.items[index].id),
                item: page.items[index],
                accountId: widget.accountId,
                onOpenLink: widget.config.onOpenLink,
                onOpenUser: widget.config.onOpenUser,
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    super.key,
    required this.item,
    required this.accountId,
    required this.onOpen,
  });
  final ForumPrivateMessageItem item;
  final String accountId;
  final MessageConversationOpener onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = item.target;
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final group = target?.kind == ForumConversationKind.group;
    final rawTitle = group
        ? item.subject
        : item.toUserName.isNotEmpty
        ? item.toUserName
        : item.fromUserId != accountId
        ? item.fromUserName
        : '';
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : group
        ? l10n.messageGroup
        : l10n.profilePrivateMessage;
    return MessageSurface(
      onTap: target == null ? null : () => onOpen(context, target, title),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MessageAvatar(
              kind: group ? MessageAvatarKind.group : MessageAvatarKind.user,
              userId: item.toUserId,
              imageUrl: item.toUserAvatarUrl,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: palette.itemTitle,
                            fontWeight: FontWeight.w700,
                            height: 1.28,
                          ),
                        ),
                      ),
                      if (item.isNew) const _UnreadBadge(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  MessagePreviewText(markup: item.message),
                  if (item.sentAt != null || item.rawDateline.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        messageTimeLabel(
                          context,
                          item.sentAt,
                          item.rawDateline,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: palette.soft,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({
    super.key,
    required this.item,
    required this.accountId,
    required this.onOpenLink,
    required this.onOpenUser,
  });
  final ForumNotificationItem item;
  final String accountId;
  final MessageLinkOpener onOpenLink;
  final MessageUserOpener onOpenUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = Theme.of(context).y300NativeContent;
    final authorLabel = item.authorName.isEmpty
        ? l10n.profileSystemNotification
        : item.authorName;
    final hasAuthor = RegExp(r'^[1-9]\d*$').hasMatch(item.authorId);
    final avatar = MessageAvatar(
      kind: hasAuthor ? MessageAvatarKind.user : MessageAvatarKind.system,
      userId: item.authorId,
      imageUrl: item.authorAvatarUrl,
    );
    return MessageSurface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (hasAuthor)
                  InkWell(
                    key: ValueKey('notification-avatar:${item.id}'),
                    customBorder: const CircleBorder(),
                    onTap: () => onOpenUser(context, item.authorId),
                    child: Semantics(
                      label: authorLabel,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(child: avatar),
                      ),
                    ),
                  )
                else
                  SizedBox.square(dimension: 48, child: Center(child: avatar)),
                const SizedBox(width: 8),
                Expanded(
                  child: hasAuthor
                      ? TextButton(
                          style: TextButton.styleFrom(
                            alignment: AlignmentDirectional.centerStart,
                            padding: EdgeInsets.zero,
                            foregroundColor: palette.author,
                            textStyle: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          onPressed: () => onOpenUser(context, item.authorId),
                          child: Text(
                            authorLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Text(
                          authorLabel,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: palette.itemTitle,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                ),
                if (item.isNew) const _UnreadBadge(),
                IconButton(
                  tooltip: l10n.messageIgnore,
                  color: palette.muted,
                  icon: const Icon(Icons.notifications_off_outlined, size: 20),
                  onPressed: () async {
                    final receipt =
                        await showDialog<ForumNotificationIgnoreReceipt>(
                          context: context,
                          builder: (_) => NotificationIgnoreDialog(
                            accountId: accountId,
                            item: item,
                          ),
                        );
                    if (receipt != null &&
                        context.mounted &&
                        ref.read(messageAccountIdProvider) == accountId) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.messageIgnoreApplied)),
                      );
                    }
                  },
                ),
              ],
            ),
            ForumHtmlContentView(
              html: item.noteMarkup,
              sourceId: 'notification:$accountId:${item.id}',
              imageCacheOwnerId: 'notification:$accountId:${item.id}',
              imageReferer: ref.watch(forumImageRefererProvider),
              surfaceColor: palette.card,
              foregroundColor: palette.body,
              onOpenLink: (url) => onOpenLink(context, url),
            ),
            if (item.duplicateCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.messageRepeatedNotifications(item.duplicateCount),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.supportingText,
                  ),
                ),
              ),
            if (item.occurredAt != null || item.rawDateline.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  messageTimeLabel(context, item.occurredAt, item.rawDateline),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: palette.soft),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 8),
    child: Badge(
      backgroundColor: Theme.of(
        context,
      ).y300NativeContent.notificationBadgeBackground,
      textColor: Theme.of(context).y300NativeContent.selectionForeground,
      label: Text(AppLocalizations.of(context).profileNewBadge),
    ),
  );
}
