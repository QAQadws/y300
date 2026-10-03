import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/forum_thread_badge_theme.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Status markers shared by forum, personal-topic and reply directories.
class ForumThreadBadgeGroup extends StatelessWidget {
  const ForumThreadBadgeGroup({super.key, required this.badges});

  final List<ForumThreadBadge> badges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final badge in badges)
          if (_label(badge, l10n).isNotEmpty)
            _ForumThreadBadge(
              label: _label(badge, l10n),
              colors: ForumThreadBadgeColors.resolve(theme, badge.kind),
            ),
      ],
    );
  }

  String _label(ForumThreadBadge badge, AppLocalizations l10n) {
    return switch (badge.kind) {
      ForumThreadBadgeKind.closed => l10n.forumThreadBadgeClosed,
      ForumThreadBadgeKind.poll => l10n.forumThreadBadgePoll,
      ForumThreadBadgeKind.trade => l10n.forumThreadBadgeTrade,
      ForumThreadBadgeKind.reward => l10n.forumThreadBadgeReward,
      ForumThreadBadgeKind.activity => l10n.forumThreadBadgeActivity,
      ForumThreadBadgeKind.debate => l10n.forumThreadBadgeDebate,
      ForumThreadBadgeKind.image => l10n.forumThreadBadgeImage,
      ForumThreadBadgeKind.sticky => l10n.forumThreadBadgeSticky,
      ForumThreadBadgeKind.digest => l10n.forumThreadBadgeDigest,
      ForumThreadBadgeKind.unknown => badge.sourceLabel.trim(),
    };
  }
}

class _ForumThreadBadge extends StatelessWidget {
  const _ForumThreadBadge({required this.label, required this.colors});

  final String label;
  final ForumThreadBadgeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 30, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: colors.foreground.withValues(alpha: 0.05),
            blurRadius: 7,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.foreground,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
