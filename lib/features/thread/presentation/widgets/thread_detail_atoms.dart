part of 'thread_detail_widgets.dart';

// Shared UI atoms and helpers for thread detail: avatar, pills, card/segment
// decorations, author initials. Moved verbatim from thread_detail_widgets.dart
// (Phase 5b file split); keys and logic unchanged.

class ThreadAuthorAvatar extends StatelessWidget {
  const ThreadAuthorAvatar({
    super.key,
    required this.author,
    required this.authorId,
    required this.avatarUrl,
    required this.palette,
    this.onTap,
  });

  final String author;
  final String authorId;
  final String? avatarUrl;
  final ThreadDetailNativePalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = avatarUrl?.trim();
    final useDefaultAvatar = isForumDefaultOrUnsupportedAvatarUrl(imageUrl);
    final placeholder = ColoredBox(
      color: palette.avatarBackground,
      child: Center(
        child: Text(
          _authorInitial(author),
          style: TextStyle(
            color: palette.avatarForeground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    final avatar = ClipOval(
      child: SizedBox(
        width: 34,
        height: 34,
        child: useDefaultAvatar
            ? ColoredBox(
                color: palette.avatarBackground,
                child: forumDefaultAvatarImage(width: 34, height: 34),
              )
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                width: 34,
                height: 34,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
    if (onTap == null) {
      return avatar;
    }
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: avatar,
    );
  }
}

class ThreadMetricPill extends StatelessWidget {
  const ThreadMetricPill({
    super.key,
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: palette.chipBackground,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.softText),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ThreadPill extends StatelessWidget {
  const ThreadPill({
    super.key,
    required this.label,
    required this.palette,
    this.emphasized = false,
  });

  final String label;
  final ThreadDetailNativePalette palette;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized
            ? palette.accent.withValues(alpha: 0.10)
            : palette.chipBackground,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: emphasized ? palette.accent : palette.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}


BoxDecoration _cardDecoration(ThreadDetailNativePalette palette) {
  return BoxDecoration(
    color: palette.card,
    borderRadius: BorderRadius.circular(12),
    boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
  );
}

BoxDecoration _highlightedCardDecoration(ThreadDetailNativePalette palette) {
  return BoxDecoration(
    color: palette.accent.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(12),
    boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
  );
}

enum _ThreadPostCardSegmentPosition { header, middle, footer }

BoxDecoration _cardSegmentDecoration({
  required ThreadDetailNativePalette palette,
  required bool highlighted,
  required _ThreadPostCardSegmentPosition position,
}) {
  final radius = switch (position) {
    _ThreadPostCardSegmentPosition.header => const BorderRadius.vertical(
      top: Radius.circular(12),
    ),
    _ThreadPostCardSegmentPosition.middle => BorderRadius.zero,
    _ThreadPostCardSegmentPosition.footer => const BorderRadius.vertical(
      bottom: Radius.circular(12),
    ),
  };
  return BoxDecoration(
    color: highlighted ? palette.accent.withValues(alpha: 0.10) : palette.card,
    borderRadius: radius,
    boxShadow: position == _ThreadPostCardSegmentPosition.header
        ? ForumNativeSurfaceShadows.card(palette.stateLayer)
        : null,
  );
}

String _authorInitial(String author) {
  final text = author.trim();
  if (text.isEmpty) {
    return '?';
  }
  return text.characters.first.toUpperCase();
}
