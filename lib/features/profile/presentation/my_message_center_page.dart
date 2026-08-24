import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';
import 'package:y300/features/profile/data/repositories/my_message_repository.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

final myMessageCenterProvider = FutureProvider.autoDispose<MyMessageCenterData>(
  (ref) async {
    final result = await ref
        .watch(myMessageRepositoryProvider)
        .getMessageCenter();
    return switch (result) {
      ApiSuccess(:final data) => data,
      ApiFailure(:final error) => throw error,
    };
  },
);

class MyMessageCenterPage extends ConsumerWidget {
  const MyMessageCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(myMessageCenterProvider);
    final imageReferer = ref.watch(forumImageRefererProvider);
    final palette = _MessageCenterPalette.resolve(Theme.of(context));

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).profileMessageCenterTitle),
      ),
      body: asyncData.when(
        data: (data) => _MessageCenterContent(
          data: data,
          palette: palette,
          imageReferer: imageReferer,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MessageCenterError(
          error: error,
          palette: palette,
          onRetry: () => ref.invalidate(myMessageCenterProvider),
        ),
      ),
    );
  }
}

class _MessageCenterContent extends StatelessWidget {
  const _MessageCenterContent({
    required this.data,
    required this.palette,
    required this.imageReferer,
  });

  final MyMessageCenterData data;
  final _MessageCenterPalette palette;
  final String imageReferer;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: palette.header,
            child: TabBar(
              key: const Key('my-message-center-tabs'),
              labelColor: palette.accent,
              unselectedLabelColor: palette.muted,
              indicatorColor: palette.accent,
              tabs: [
                Tab(
                  text: AppLocalizations.of(
                    context,
                  ).profileNotificationsTab(data.notifications.count),
                ),
                Tab(
                  text: AppLocalizations.of(
                    context,
                  ).profileMessagesTab(data.privateMessages.count),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _NotificationList(
                  page: data.notifications,
                  palette: palette,
                  imageReferer: imageReferer,
                ),
                _PrivateMessageList(
                  page: data.privateMessages,
                  palette: palette,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.page,
    required this.palette,
    required this.imageReferer,
  });

  final MyNotificationPage page;
  final _MessageCenterPalette palette;
  final String imageReferer;

  @override
  Widget build(BuildContext context) {
    if (page.items.isEmpty) {
      return _EmptyState(
        icon: Icons.notifications_none,
        text: AppLocalizations.of(context).profileNoNotifications,
        palette: palette,
      );
    }
    return ListView.separated(
      key: const Key('my-notification-list'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      itemCount: page.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = page.items[index];
        return _MessageCard(
          key: Key('my-notification-${item.id}'),
          palette: palette,
          isNew: item.isNew,
          leading: Icons.notifications_active_outlined,
          title: _notificationTitle(context, item),
          subtitle: item.dateline,
          child: DefaultTextStyle.merge(
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.body, height: 1.45),
            child: ForumHtmlContentView(
              html: item.noteHtml,
              sourceId: 'my-notification-${item.id}',
              imageCacheOwnerId: item.id,
              contentImageKind: ForumImageKind.blogInline,
              imageReferer: imageReferer,
              surfaceColor: palette.card,
              foregroundColor: palette.body,
              onOpenLink: (url) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(url))),
            ),
          ),
        );
      },
    );
  }

  String _notificationTitle(BuildContext context, MyNotificationItem item) {
    final author = item.author.trim();
    if (author.isEmpty) {
      return item.type.isEmpty
          ? AppLocalizations.of(context).profileSystemNotification
          : item.type;
    }
    return author;
  }
}

class _PrivateMessageList extends StatelessWidget {
  const _PrivateMessageList({required this.page, required this.palette});

  final MyPrivateMessagePage page;
  final _MessageCenterPalette palette;

  @override
  Widget build(BuildContext context) {
    if (page.items.isEmpty) {
      return _EmptyState(
        icon: Icons.mail_outline,
        text: AppLocalizations.of(context).profileNoMessages,
        palette: palette,
      );
    }
    return ListView.separated(
      key: const Key('my-private-message-list'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      itemCount: page.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = page.items[index];
        return _MessageCard(
          key: Key('my-private-message-${item.pmid}'),
          palette: palette,
          isNew: item.isNew,
          leading: Icons.mail_outline,
          title: item.subject.trim().isEmpty
              ? AppLocalizations.of(context).profilePrivateMessage
              : item.subject,
          subtitle: _messageSubtitle(context, item),
          child: Text(
            item.message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.body, height: 1.45),
          ),
        );
      },
    );
  }

  String _messageSubtitle(BuildContext context, MyPrivateMessageItem item) {
    final names = <String>[
      if (item.fromName.trim().isNotEmpty) item.fromName.trim(),
      if (item.toName.trim().isNotEmpty)
        AppLocalizations.of(context).profileMessageTo(item.toName.trim()),
    ];
    if (item.dateline.trim().isNotEmpty) {
      names.add(item.dateline.trim());
    }
    return names.join(' · ');
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    super.key,
    required this.palette,
    required this.isNew,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final _MessageCenterPalette palette;
  final bool isNew;
  final IconData leading;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: palette.iconBackground,
                foregroundColor: palette.accent,
                child: Icon(leading, size: 18),
              ),
              const SizedBox(width: 10),
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
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: palette.title,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: 8),
                          _NewBadge(palette: palette),
                        ],
                      ],
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(color: palette.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge({required this.palette});

  final _MessageCenterPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.badgeBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          AppLocalizations.of(context).profileNewBadge,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: palette.badgeForeground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.text,
    required this.palette,
  });

  final IconData icon;
  final String text;
  final _MessageCenterPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: palette.muted),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: palette.muted)),
        ],
      ),
    );
  }
}

class _MessageCenterError extends StatelessWidget {
  const _MessageCenterError({
    required this.error,
    required this.palette,
    required this.onRetry,
  });

  final Object error;
  final _MessageCenterPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: palette.accent, size: 34),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).profileMessagesLoadFailed(
                LocalizedErrorSummary.resolve(
                  AppLocalizations.of(context),
                  error,
                ),
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.body),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _MessageCenterPalette {
  const _MessageCenterPalette({
    required this.background,
    required this.header,
    required this.card,
    required this.title,
    required this.body,
    required this.muted,
    required this.accent,
    required this.iconBackground,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.shadow,
  });

  final Color background;
  final Color header;
  final Color card;
  final Color title;
  final Color body;
  final Color muted;
  final Color accent;
  final Color iconBackground;
  final Color badgeBackground;
  final Color badgeForeground;
  final Color shadow;

  static _MessageCenterPalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final appBarBackground =
        theme.appBarTheme.backgroundColor ?? scheme.primary;
    final native = theme.y300NativeContent;
    if (isDark) {
      return _MessageCenterPalette(
        background: theme.scaffoldBackgroundColor,
        header: scheme.surfaceContainer,
        card: scheme.surfaceContainerHigh,
        title: scheme.onSurface,
        body: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        accent: scheme.primary,
        iconBackground: scheme.primaryContainer,
        badgeBackground: scheme.secondaryContainer,
        badgeForeground: scheme.onSecondaryContainer,
        shadow: Colors.black.withValues(alpha: 0.20),
      );
    }
    return _MessageCenterPalette(
      background: native.background,
      header: native.card,
      card: native.card,
      title: native.title,
      body: native.body,
      muted: native.tertiaryText,
      accent: appBarBackground,
      iconBackground: appBarBackground.withValues(alpha: 0.10),
      badgeBackground: native.notificationBadgeBackground,
      badgeForeground: native.avatarForeground,
      shadow: appBarBackground.withValues(alpha: 0.07),
    );
  }
}
