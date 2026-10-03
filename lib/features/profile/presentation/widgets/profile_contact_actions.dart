import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/l10n/app_localizations.dart';

/// The page supplies only actions available to the current forum session.
class ProfileContactActions extends StatelessWidget {
  const ProfileContactActions({
    super.key,
    this.onSendMessage,
    this.onAddFriend,
    this.onRemoveFriend,
  });

  final VoidCallback? onSendMessage;
  final VoidCallback? onAddFriend;
  final VoidCallback? onRemoveFriend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.y300NativeContent;
    final l10n = AppLocalizations.of(context);
    final actions = [
      if (onSendMessage != null)
        (
          name: 'sendMessage',
          label: l10n.profileSendMessage,
          icon: Icons.mail_outline_rounded,
          color: theme.colorScheme.primary,
          onPressed: onSendMessage!,
        ),
      if (onAddFriend != null)
        (
          name: 'addFriend',
          label: l10n.profileAddFriend,
          icon: Icons.person_add_alt_outlined,
          color: colors.supportingText,
          onPressed: onAddFriend!,
        ),
      if (onRemoveFriend != null)
        (
          name: 'removeFriend',
          label: l10n.profileRemoveFriend,
          icon: Icons.person_remove_outlined,
          color: colors.supportingText,
          onPressed: onRemoveFriend!,
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('user-profile-contact-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final large = MediaQuery.textScalerOf(context).scale(14) > 20;
            // Each action retains a comfortable target at narrow widths or large type.
            final columnWidth =
                (constraints.maxWidth - (actions.length - 1) * 8) /
                actions.length;
            final inline = !large && columnWidth >= 136;
            final width = inline ? columnWidth : constraints.maxWidth;
            return Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: width,
                    child: TextButton.icon(
                      key: Key('user-profile-action-${action.name}'),
                      onPressed: action.onPressed,
                      style: TextButton.styleFrom(
                        foregroundColor: action.color,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(action.icon, size: 20),
                      label: Text(action.label, textAlign: TextAlign.center),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
