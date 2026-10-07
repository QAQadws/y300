import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/messages/domain/private_message_recipient_selection.dart';
import 'package:y300/l10n/app_localizations.dart';

class PrivateMessageRecipientBar extends StatelessWidget {
  const PrivateMessageRecipientBar({
    super.key,
    required this.selection,
    required this.onPressed,
  });

  final PrivateMessageRecipientSelection selection;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final l10n = AppLocalizations.of(context);
    final summary = selection.isEmpty
        ? l10n.messageChooseRecipients
        : selection.items.map((item) => item.username).join('、');
    return Material(
      color: palette.card,
      child: InkWell(
        key: const Key('message-friends-open'),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.messageRecipients,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.supportingText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.body,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.messageRecipientCountCompact(selection.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.supportingText,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: palette.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
