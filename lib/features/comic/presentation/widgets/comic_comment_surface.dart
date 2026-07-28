import 'package:flutter/material.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';
import 'package:y300/l10n/app_localizations.dart';

enum ComicCommentFeedbackKind {
  loading,
  empty,
  unavailable,
  open,
  advance,
  lastChapter,
}

/// Shared feedback surface for comment list and reader-tail states.
///
/// Keeping this surface independent from the session controller makes all
/// transient states use the same copy, palette, spacing and accessibility
/// semantics without coupling the reader engine to comic UI details.
class ComicCommentFeedbackSurface extends StatelessWidget {
  const ComicCommentFeedbackSurface({
    super.key,
    required this.kind,
    this.onAction,
    this.actionKey,
    this.nextEpisodeTitle,
    this.compact = false,
  });

  final ComicCommentFeedbackKind kind;
  final VoidCallback? onAction;
  final Key? actionKey;
  final String? nextEpisodeTitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
    final l10n = AppLocalizations.of(context);
    final message = _message(l10n);
    final isLoading = kind == ComicCommentFeedbackKind.loading;
    final isAction =
        kind == ComicCommentFeedbackKind.unavailable ||
        kind == ComicCommentFeedbackKind.open;
    final content = switch (kind) {
      ComicCommentFeedbackKind.loading => _LoadingContent(
        message: message,
        foreground: palette.muted,
      ),
      ComicCommentFeedbackKind.empty => _MessageContent(
        icon: Icons.forum_outlined,
        message: message,
        foreground: palette.muted,
      ),
      ComicCommentFeedbackKind.lastChapter => _MessageContent(
        icon: Icons.done_all,
        message: message,
        foreground: palette.muted,
      ),
      ComicCommentFeedbackKind.advance => _MessageContent(
        icon: Icons.swipe_outlined,
        message: message,
        foreground: palette.muted,
      ),
      ComicCommentFeedbackKind.unavailable => _ActionContent(
        icon: Icons.cloud_off_outlined,
        message: message,
        actionLabel: l10n.commonRetry,
        foreground: palette.muted,
        onAction: onAction,
        actionKey: actionKey,
      ),
      ComicCommentFeedbackKind.open => _ActionContent(
        icon: Icons.forum_outlined,
        message: message,
        actionLabel: l10n.comicCommentOpen,
        foreground: palette.muted,
        onAction: onAction,
        actionKey: actionKey,
        showMessage: false,
      ),
    };
    final surface = Container(
      margin: EdgeInsets.fromLTRB(12, compact ? 4 : 12, 12, compact ? 8 : 12),
      constraints: BoxConstraints(minHeight: compact ? 72 : 132),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 20,
        vertical: compact ? 10 : 24,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
      ),
      child: Center(child: content),
    );
    return Semantics(
      container: true,
      liveRegion: isLoading || kind == ComicCommentFeedbackKind.unavailable,
      label: isAction ? null : message,
      child: isAction ? surface : ExcludeSemantics(child: surface),
    );
  }

  String _message(AppLocalizations l10n) {
    return switch (kind) {
      ComicCommentFeedbackKind.loading => l10n.comicCommentLoading,
      ComicCommentFeedbackKind.empty => l10n.comicCommentEmpty,
      ComicCommentFeedbackKind.unavailable => l10n.comicCommentUnavailable,
      ComicCommentFeedbackKind.open => l10n.comicCommentOpen,
      ComicCommentFeedbackKind.advance => _advanceMessage(l10n),
      ComicCommentFeedbackKind.lastChapter => l10n.comicLastEpisode,
    };
  }

  String _advanceMessage(AppLocalizations l10n) {
    final title = nextEpisodeTitle?.trim();
    return title == null || title.isEmpty
        ? l10n.comicCommentContinue
        : l10n.comicCommentContinueTo(title);
  }
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent({required this.message, required this.foreground});

  final String message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hourglass_top_outlined, color: foreground),
        const SizedBox(height: 10),
        Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: foreground),
        ),
      ],
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.icon,
    required this.message,
    required this.foreground,
  });

  final IconData icon;
  final String message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: foreground),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: foreground),
        ),
      ],
    );
  }
}

class _ActionContent extends StatelessWidget {
  const _ActionContent({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.foreground,
    required this.onAction,
    this.actionKey,
    this.showMessage = true,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final Color foreground;
  final VoidCallback? onAction;
  final Key? actionKey;
  final bool showMessage;

  @override
  Widget build(BuildContext context) {
    if (!showMessage) {
      return OutlinedButton.icon(
        key: actionKey,
        onPressed: onAction,
        icon: Icon(icon),
        label: Text(actionLabel),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: foreground),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            message,
            key: const Key('comic-comment-failure'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: foreground),
          ),
        ),
        if (onAction != null) ...[
          const SizedBox(width: 8),
          TextButton(
            key: actionKey,
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ],
    );
  }
}
