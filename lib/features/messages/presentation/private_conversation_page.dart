import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/widgets/message_avatar.dart';
import 'package:y300/features/messages/presentation/widgets/message_feed_view.dart';
import 'package:y300/features/messages/presentation/widgets/message_read_status.dart';
import 'package:y300/features/messages/presentation/widgets/private_message_editor.dart';
import 'package:y300/features/messages/presentation/widgets/message_surface.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_settings_sheet.dart';
import 'package:y300/l10n/app_localizations.dart';

typedef MessageLinkOpener = void Function(BuildContext context, String url);

class PrivateConversationPage extends ConsumerWidget {
  const PrivateConversationPage({
    super.key,
    required this.target,
    required this.onOpenLink,
    this.title = '',
  });
  final ForumConversationTarget target;
  final String title;
  final MessageLinkOpener onOpenLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(messageAccountIdProvider);
    final l10n = AppLocalizations.of(context);
    final label = title.isNotEmpty
        ? title
        : target.kind == ForumConversationKind.group
        ? l10n.messageGroup
        : l10n.profilePrivateMessage;
    if (account == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).y300NativeContent.background,
        appBar: AppBar(title: Text(label)),
        body: const MessageLoginPrompt(),
      );
    }
    return _ConversationBody(
      key: ValueKey((account, target)),
      accountId: account,
      target: target,
      title: label,
      onOpenLink: onOpenLink,
    );
  }
}

class _ConversationBody extends ConsumerStatefulWidget {
  const _ConversationBody({
    super.key,
    required this.accountId,
    required this.target,
    required this.title,
    required this.onOpenLink,
  });
  final String accountId;
  final ForumConversationTarget target;
  final String title;
  final MessageLinkOpener onOpenLink;

  @override
  ConsumerState<_ConversationBody> createState() => _ConversationBodyState();
}

class _ConversationBodyState extends ConsumerState<_ConversationBody> {
  final _timeline = GlobalKey<_ConversationTimelineState>();

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(privateMessageFeedProvider(widget.target));
    final imageReferer = ref.watch(forumImageRefererProvider);
    final l10n = AppLocalizations.of(context);
    return MessageFeedView(
      controller: controller,
      builder: (context, state) => Scaffold(
        backgroundColor: Theme.of(context).y300NativeContent.background,
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: l10n.messageRefresh,
              onPressed: state.isBusy ? null : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: l10n.threadHtmlConversionSettings,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ForumHtmlReaderSettingsSheet(
                  showConversionControls: true,
                ),
              ),
              icon: const Icon(Icons.text_fields),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (state.isBusy && state.data != null)
                LinearProgressIndicator(
                  color: Theme.of(context).y300NativeContent.accent,
                  value: MediaQuery.disableAnimationsOf(context) ? 0.5 : null,
                ),
              if (state.failure != null && state.data != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.25,
                  ),
                  child: SingleChildScrollView(
                    child: MessageReadStatus(
                      failure: state.failure,
                      onRetry: controller.refresh,
                    ),
                  ),
                ),
              Expanded(
                child: state.data == null
                    ? Center(
                        child: MessageReadStatus(
                          failure: state.failure,
                          onRetry: controller.refresh,
                        ),
                      )
                    : _ConversationTimeline(
                        key: _timeline,
                        page: state.data!,
                        accountId: widget.accountId,
                        target: widget.target,
                        controller: controller,
                        imageReferer: imageReferer,
                        onOpenLink: widget.onOpenLink,
                      ),
              ),
              if (state.data != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.55,
                  ),
                  child: PrivateMessageEditor(
                    key: ValueKey(widget.accountId),
                    accountId: widget.accountId,
                    recipient:
                        widget.target.kind == ForumConversationKind.direct
                        ? ForumPrivateMessageRecipient.user(widget.target.id)
                        : ForumPrivateMessageRecipient.group(
                            conversationId: widget.target.id,
                            replyMessageId: state.data!.replyMessageId,
                          ),
                    enabled:
                        widget.target.kind == ForumConversationKind.direct ||
                        state.data!.replyMessageId.isNotEmpty,
                    onApplied: (_) {
                      _timeline.currentState?.showLatest();
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(l10n.messageSent)));
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTimeline extends StatefulWidget {
  const _ConversationTimeline({
    super.key,
    required this.page,
    required this.accountId,
    required this.target,
    required this.controller,
    required this.imageReferer,
    required this.onOpenLink,
  });
  final ForumPrivateMessagePage page;
  final String accountId;
  final ForumConversationTarget target;
  final MessageFeedController<ForumPrivateMessagePage> controller;
  final String imageReferer;
  final MessageLinkOpener onOpenLink;

  @override
  State<_ConversationTimeline> createState() => _ConversationTimelineState();
}

class _ConversationTimelineState extends State<_ConversationTimeline> {
  final _scroll = ScrollController();
  final _center = GlobalKey();
  String? _anchor;
  bool _awayFromLatest = false;

  @override
  void initState() {
    super.initState();
    _anchor = widget.page.items.lastOrNull?.messageId;
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final away =
        _scroll.position.pixels - _scroll.position.minScrollExtent > 80;
    if (away != _awayFromLatest) setState(() => _awayFromLatest = away);
  }

  @override
  void didUpdateWidget(covariant _ConversationTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.page.items.any((item) => item.messageId == _anchor)) {
      _anchor = widget.page.items.lastOrNull?.messageId;
      _awayFromLatest = false;
      showLatest();
    }
    if (!_awayFromLatest &&
        oldWidget.page.items.lastOrNull?.messageId !=
            widget.page.items.lastOrNull?.messageId) {
      showLatest();
    }
  }

  void showLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.minScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.page.items;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(context).profileNoMessages,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).y300NativeContent.supportingText,
            ),
          ),
        ),
      );
    }
    final split = items.indexWhere((item) => item.messageId == _anchor) + 1;
    final history = items.take(split).toList().reversed.toList();
    final newer = items.skip(split).toList();
    Widget bubble(ForumPrivateMessageItem item) => _MessageBubble(
      key: ValueKey(item.messageId),
      item: item,
      accountId: widget.accountId,
      target: widget.target,
      imageReferer: widget.imageReferer,
      onOpenLink: widget.onOpenLink,
    );
    // A stable center separates older and newer messages. Both ends may grow
    // without moving the content the user is currently reading, even for HTML
    // rows of different heights. Avoid estimated scroll-offset corrections.
    return Stack(
      children: [
        CustomScrollView(
          key: const Key('private-conversation-list'),
          controller: _scroll,
          reverse: true,
          center: _center,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverList.builder(
              itemCount: newer.length,
              itemBuilder: (_, index) => bubble(newer[index]),
            ),
            SliverList.builder(
              key: _center,
              itemCount: history.length + 1,
              itemBuilder: (context, index) => index < history.length
                  ? bubble(history[index])
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: widget.controller.hasMore
                          ? TextButton(
                              onPressed: widget.controller.value.isBusy
                                  ? null
                                  : widget.controller.loadMore,
                              child: Text(
                                AppLocalizations.of(context).messageOlder,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
            ),
          ],
        ),
        if (_awayFromLatest)
          Positioned.directional(
            textDirection: Directionality.of(context),
            end: 12,
            bottom: 8,
            child: FilledButton.tonalIcon(
              onPressed: showLatest,
              icon: const Icon(Icons.arrow_downward, size: 18),
              label: Text(AppLocalizations.of(context).messageLatest),
            ),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.item,
    required this.accountId,
    required this.target,
    required this.imageReferer,
    required this.onOpenLink,
  });
  final ForumPrivateMessageItem item;
  final String accountId;
  final ForumConversationTarget target;
  final String imageReferer;
  final MessageLinkOpener onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final outgoing = item.fromUserId == accountId;
    final surface = outgoing
        ? Color.alphaBlend(palette.accent.withValues(alpha: 0.10), palette.card)
        : palette.card;
    final foreground = palette.body;
    final identity =
        'private:$accountId:${target.kind.name}:${target.id}:${item.messageId}';
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        outgoing ? 32 : 12,
        6,
        outgoing ? 12 : 32,
        6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!outgoing) ...[
            MessageAvatar(
              userId: item.fromUserId,
              imageUrl: item.fromUserAvatarUrl,
              size: 36,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: MessageSurface(
              color: surface,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.fromUserName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          item.fromUserName,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: palette.author,
                          ),
                        ),
                      ),
                    ForumHtmlContentView(
                      html: item.message,
                      sourceId: identity,
                      imageCacheOwnerId: identity,
                      imageReferer: imageReferer,
                      surfaceColor: surface,
                      foregroundColor: foreground,
                      onOpenLink: (url) => onOpenLink(context, url),
                    ),
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
            ),
          ),
          if (outgoing) ...[
            const SizedBox(width: 8),
            MessageAvatar(
              userId: item.fromUserId,
              imageUrl: item.fromUserAvatarUrl,
              size: 36,
            ),
          ],
        ],
      ),
    );
  }
}
