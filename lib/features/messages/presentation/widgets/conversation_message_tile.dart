import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/messages/presentation/conversation_message_presentation.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/widgets/message_avatar.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/l10n/app_localizations.dart';

class ConversationMessageTile extends StatelessWidget {
  const ConversationMessageTile({
    super.key,
    required this.presentation,
    required this.accountId,
    required this.target,
    required this.imageReferer,
    required this.onOpenLink,
  });

  final ConversationMessagePresentation presentation;
  final String accountId;
  final ForumConversationTarget target;
  final String imageReferer;
  final void Function(BuildContext context, String url) onOpenLink;

  ForumPrivateMessageItem get _item => presentation.item;
  String get _identity =>
      'private:$accountId:${target.kind.name}:${target.id}:${_item.messageId}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final l10n = AppLocalizations.of(context);
    final outgoing = _item.fromUserId == accountId;
    final surface = outgoing
        ? Color.alphaBlend(palette.accent.withValues(alpha: 0.10), palette.card)
        : palette.card;
    final showAuthor =
        target.kind == ForumConversationKind.group &&
        !outgoing &&
        presentation.isGroupStart;
    final author = _authorLabel(context, _item);
    final gap = presentation.isFirst
        ? 0.0
        : presentation.isGroupStart
        ? 12.0
        : 4.0;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, gap, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (presentation.showTimestamp)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _timestampLabel(context, _item),
                key: ValueKey('message-time:${_item.messageId}'),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: palette.soft,
                ),
              ),
            ),
          if (showAuthor)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 56, bottom: 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  author,
                  key: ValueKey('message-author:${_item.messageId}'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: palette.author,
                  ),
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final bubbleWidth = math.max(
                0.0,
                math.min(
                  math.min(constraints.maxWidth * 0.78, 560.0),
                  constraints.maxWidth - 56,
                ),
              );
              final avatar = presentation.isGroupStart
                  ? _ConversationAvatar(item: _item, onOpenLink: onOpenLink)
                  : const SizedBox.square(dimension: 48);
              final bubble = Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bubbleWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: outgoing
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        container: true,
                        label:
                            '$author · ${_fullTimestampLabel(context, _item)}',
                        onLongPress: () => _showDetails(context),
                        onLongPressHint: l10n.messageDetails,
                        child: Material(
                          key: ValueKey(
                            'conversation-bubble-${_item.messageId}',
                          ),
                          color: surface,
                          elevation: 0,
                          surfaceTintColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            excludeFromSemantics: true,
                            onLongPress: () => _showDetails(context),
                            borderRadius: BorderRadius.circular(16),
                            overlayColor: WidgetStatePropertyAll(
                              palette.subtleStateLayer,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: ForumHtmlContentView(
                                html: _item.message,
                                sourceId: _identity,
                                imageCacheOwnerId: _identity,
                                imageReferer: imageReferer,
                                surfaceColor: surface,
                                foregroundColor: palette.body,
                                contentLayout: ForumHtmlContentLayout.compact,
                                onOpenLink: (url) => onOpenLink(context, url),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
              return Row(
                mainAxisAlignment: outgoing
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: outgoing
                    ? [bubble, const SizedBox(width: 8), avatar]
                    : [avatar, const SizedBox(width: 8), bubble],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).y300NativeContent.card,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          if (ref.watch(messageAccountIdProvider) != accountId) {
            // A modal is a separate route and can outlive the account's page.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted &&
                  ModalRoute.of(context)?.isCurrent == true) {
                Navigator.of(context).pop();
              }
            });
            return const SizedBox.shrink();
          }
          return _ConversationMessageDetails(
            item: _item,
            identity: _identity,
            imageReferer: imageReferer,
            onOpenLink: onOpenLink,
          );
        },
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.item, required this.onOpenLink});

  final ForumPrivateMessageItem item;
  final void Function(BuildContext context, String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final avatar = SizedBox.square(
      dimension: 48,
      child: Center(
        child: MessageAvatar(
          userId: item.fromUserId,
          imageUrl: item.fromUserAvatarUrl,
          size: 36,
        ),
      ),
    );
    if (!RegExp(r'^[1-9]\d*$').hasMatch(item.fromUserId)) return avatar;
    return Tooltip(
      message: AppLocalizations.of(
        context,
      ).messageOpenProfile(_authorLabel(context, item)),
      child: InkWell(
        key: ValueKey('message-avatar:${item.messageId}'),
        customBorder: const CircleBorder(),
        onTap: () =>
            onOpenLink(context, 'home.php?mod=space&uid=${item.fromUserId}'),
        child: avatar,
      ),
    );
  }
}

class _ConversationMessageDetails extends StatelessWidget {
  const _ConversationMessageDetails({
    required this.item,
    required this.identity,
    required this.imageReferer,
    required this.onOpenLink,
  });

  final ForumPrivateMessageItem item;
  final String identity;
  final String imageReferer;
  final void Function(BuildContext context, String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.messageDetails,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: palette.itemTitle,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _authorLabel(context, item),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: palette.author,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fullTimestampLabel(context, item),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.soft,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ForumHtmlContentView(
                          html: item.message,
                          sourceId: '$identity:details',
                          imageCacheOwnerId: identity,
                          imageReferer: imageReferer,
                          surfaceColor: palette.card,
                          foregroundColor: palette.body,
                          onOpenLink: (url) => onOpenLink(context, url),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _authorLabel(BuildContext context, ForumPrivateMessageItem item) =>
    item.fromUserName.trim().isNotEmpty
    ? item.fromUserName
    : item.fromUserId.trim().isNotEmpty
    ? item.fromUserId
    : AppLocalizations.of(context).threadRatingUnknownUser;

String _timestampLabel(BuildContext context, ForumPrivateMessageItem item) {
  final time = item.sentAt?.toLocal();
  if (time == null) return _fullTimestampLabel(context, item);
  final localizations = MaterialLocalizations.of(context);
  final clock = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(time),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) return clock;
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return AppLocalizations.of(context).messageYesterdayTime(clock);
  }
  final date = DateFormat.yMd(
    AppLocalizations.of(context).localeName,
  ).format(time);
  return '$date · $clock';
}

String _fullTimestampLabel(BuildContext context, ForumPrivateMessageItem item) {
  final l10n = AppLocalizations.of(context);
  final time = item.sentAt?.toLocal();
  if (time == null) {
    final raw = item.rawDateline.trim();
    return raw.isNotEmpty ? raw : l10n.messageTimeUnknown;
  }
  final format = DateFormat.yMd(l10n.localeName);
  return (MediaQuery.alwaysUse24HourFormatOf(context)
          ? format.add_Hms()
          : format.add_jms())
      .format(time);
}
