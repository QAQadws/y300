import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/tags/domain/models/forum_tag_directory_models.dart';
import 'package:y300/features/tags/domain/repositories/forum_tag_directory_repository.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';
import 'package:y300/shared/widgets/native_page_dropdown_button.dart';

class YamiboTagThreadPage extends ConsumerWidget {
  const YamiboTagThreadPage({
    super.key,
    required this.tagId,
    this.page = 1,
    this.title = '',
  });

  final String tagId;
  final int page;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = YamiboTagThreadPageArgs(
      tagId: tagId,
      page: page,
      title: title,
    );
    final asyncState = ref.watch(yamiboTagThreadPageControllerProvider(args));
    final controller = ref.read(
      yamiboTagThreadPageControllerProvider(args).notifier,
    );
    final state = asyncState.value ?? YamiboTagThreadPageState.initial(args);
    final palette = ForumDisplayThemePalette.resolve(Theme.of(context));
    final data = state.data;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      key: const Key('yamibo-tag-thread-page'),
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(
          data?.tag.name?.trim().isNotEmpty == true
              ? data!.tag.name!
              : (state.title.trim().isNotEmpty
                    ? state.title
                    : l10n.tagTitleFallback),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: asyncState.isLoading && data == null
          ? const Center(child: CircularProgressIndicator())
          : data == null
          ? _TagPageErrorView(
              message: l10n.tagLoadFailed(
                LocalizedErrorSummary.resolve(l10n, state.errorMessage),
              ),
              onRetry: controller.refresh,
              palette: palette,
            )
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                key: const Key('yamibo-tag-thread-list'),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
                children: [
                  _TagHeaderCard(data: data, palette: palette),
                  const SizedBox(height: 8),
                  if (state.errorMessage?.trim().isNotEmpty == true)
                    _InlineError(
                      message: l10n.tagLoadFailed(
                        LocalizedErrorSummary.resolve(l10n, state.errorMessage),
                      ),
                      palette: palette,
                    ),
                  if (data.topics.isEmpty)
                    _EmptyTagThreadList(palette: palette)
                  else
                    for (final thread in data.topics)
                      _TagThreadCard(
                        thread: thread,
                        capabilities: state.capabilities,
                        palette: palette,
                        onTap: () => _openThread(context, thread),
                      ),
                  _TagPager(
                    data: data,
                    capabilities: state.capabilities,
                    isLoading: state.isLoadingPage,
                    palette: palette,
                    onSelectPage: controller.loadPage,
                  ),
                ],
              ),
            ),
    );
  }

  void _openThread(BuildContext context, ForumTagTopicSummary thread) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ThreadDetailPage(tid: thread.tid, subject: thread.title),
      ),
    );
  }
}

class _TagHeaderCard extends StatelessWidget {
  const _TagHeaderCard({required this.data, required this.palette});

  final ForumTagDirectoryData data;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final total = data.pagination.totalPages;
    final page = data.pagination.currentPage;
    final pageLabel = total == null
        ? AppLocalizations.of(context).commonPage(page)
        : AppLocalizations.of(context).commonPageOf(page, total);
    return DecoratedBox(
      key: const Key('yamibo-tag-header-card'),
      decoration: _tagSurfaceDecoration(palette),
      child: Material(
        color: palette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.sell_outlined, size: 17, color: palette.accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  data.tag.name ??
                      AppLocalizations.of(context).tagTitleFallback,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: palette.title,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                ),
                child: Text(
                  pageLabel,
                  key: const Key('yamibo-tag-header-page-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.softText,
                    fontWeight: FontWeight.w600,
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

class _TagThreadCard extends StatefulWidget {
  const _TagThreadCard({
    required this.thread,
    required this.capabilities,
    required this.palette,
    required this.onTap,
  });

  final ForumTagTopicSummary thread;
  final ForumTagDirectoryReadCapabilities? capabilities;
  final ForumDisplayThemePalette palette;
  final VoidCallback onTap;

  @override
  State<_TagThreadCard> createState() => _TagThreadCardState();
}

class _TagThreadCardState extends State<_TagThreadCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final capabilities = widget.capabilities;
    final palette = widget.palette;
    final textTheme = Theme.of(context).textTheme;
    final lastPostLine = <String>[
      if (capabilities?.supports(ForumTagDirectoryCapability.topicLastPost) ==
              true &&
          thread.lastPosterName?.trim().isNotEmpty == true)
        thread.lastPosterName!,
      if (capabilities?.supports(ForumTagDirectoryCapability.topicLastPost) ==
              true &&
          thread.lastPostAt?.trim().isNotEmpty == true)
        thread.lastPostAt!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        scale: _isPressed ? 0.985 : 1,
        child: DecoratedBox(
          key: Key('yamibo-tag-thread-surface-${thread.tid}'),
          decoration: _tagSurfaceDecoration(palette),
          child: Material(
            color: palette.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('yamibo-tag-thread-${thread.tid}'),
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTap,
              onHighlightChanged: (isHighlighted) {
                if (_isPressed != isHighlighted) {
                  setState(() => _isPressed = isHighlighted);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: _isPressed
                      ? Color.alphaBlend(
                          palette.stateLayer,
                          palette.surfaceContainerLow,
                        )
                      : palette.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            thread.title,
                            key: Key('yamibo-tag-thread-title-${thread.tid}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              color: palette.threadTitle,
                              fontWeight: FontWeight.w700,
                              height: 1.28,
                            ),
                          ),
                        ),
                        if (capabilities?.supports(
                                  ForumTagDirectoryCapability
                                      .topicAttachmentFlags,
                                ) ==
                                true &&
                            thread.hasImageAttachment == true) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.image_outlined,
                            key: Key(
                              'yamibo-tag-thread-attachment-${thread.tid}',
                            ),
                            size: 16,
                            color: palette.softText,
                          ),
                        ],
                      ],
                    ),
                    if (_hasAuthorMetadata(thread)) ...[
                      const SizedBox(height: 6),
                      _TagAuthorMetadata(
                        thread: thread,
                        capabilities: capabilities,
                        palette: palette,
                      ),
                    ],
                    if (lastPostLine.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        AppLocalizations.of(context).tagLastPost(lastPostLine),
                        key: Key('yamibo-tag-thread-last-post-${thread.tid}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.softText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (_hasFooterMetadata(thread)) ...[
                      const SizedBox(height: 9),
                      _TagThreadFooter(
                        thread: thread,
                        capabilities: capabilities,
                        palette: palette,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _hasAuthorMetadata(ForumTagTopicSummary thread) {
    final canAuthor =
        widget.capabilities?.supports(
          ForumTagDirectoryCapability.topicAuthor,
        ) ==
        true;
    final canCreatedAt =
        widget.capabilities?.supports(
          ForumTagDirectoryCapability.topicCreationTime,
        ) ==
        true;
    return (canAuthor && thread.authorName?.trim().isNotEmpty == true) ||
        (canCreatedAt && thread.createdAt?.trim().isNotEmpty == true);
  }

  bool _hasFooterMetadata(ForumTagTopicSummary thread) {
    final canForum =
        widget.capabilities?.supports(ForumTagDirectoryCapability.topicForum) ==
        true;
    final canReplies =
        widget.capabilities?.supports(
          ForumTagDirectoryCapability.topicReplyCount,
        ) ==
        true;
    final canViews =
        widget.capabilities?.supports(
          ForumTagDirectoryCapability.topicViewCount,
        ) ==
        true;
    return (canReplies && thread.replyCount != null) ||
        (canViews && thread.viewCount != null) ||
        (canForum && thread.forumName?.trim().isNotEmpty == true);
  }
}

class _TagAuthorMetadata extends StatelessWidget {
  const _TagAuthorMetadata({
    required this.thread,
    required this.capabilities,
    required this.palette,
  });

  final ForumTagTopicSummary thread;
  final ForumTagDirectoryReadCapabilities? capabilities;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final author =
        capabilities?.supports(ForumTagDirectoryCapability.topicAuthor) == true
        ? thread.authorName?.trim()
        : null;
    final createdAt =
        capabilities?.supports(ForumTagDirectoryCapability.topicCreationTime) ==
            true
        ? thread.createdAt?.trim()
        : null;
    final baseStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: palette.softText,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          if (author?.isNotEmpty == true)
            TextSpan(
              text: author,
              style: baseStyle?.copyWith(
                color: palette.author,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (author?.isNotEmpty == true && createdAt?.isNotEmpty == true)
            const TextSpan(text: ' · '),
          if (createdAt?.isNotEmpty == true) TextSpan(text: createdAt),
        ],
      ),
      key: Key('yamibo-tag-thread-author-${thread.tid}'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _TagThreadFooter extends StatelessWidget {
  const _TagThreadFooter({
    required this.thread,
    required this.capabilities,
    required this.palette,
  });

  final ForumTagTopicSummary thread;
  final ForumTagDirectoryReadCapabilities? capabilities;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final forumName =
        capabilities?.supports(ForumTagDirectoryCapability.topicForum) == true
        ? thread.forumName?.trim()
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (capabilities?.supports(
                        ForumTagDirectoryCapability.topicReplyCount,
                      ) ==
                      true &&
                  thread.replyCount != null)
                _TagMetric(
                  key: Key('yamibo-tag-thread-replies-${thread.tid}'),
                  icon: Icons.chat_bubble_outline,
                  value: thread.replyCount!,
                  semanticsLabel: l10n.tagReplies(thread.replyCount!),
                  palette: palette,
                ),
              if (capabilities?.supports(
                        ForumTagDirectoryCapability.topicViewCount,
                      ) ==
                      true &&
                  thread.viewCount != null)
                _TagMetric(
                  key: Key('yamibo-tag-thread-views-${thread.tid}'),
                  icon: Icons.visibility_outlined,
                  value: thread.viewCount!,
                  semanticsLabel: l10n.tagViews(thread.viewCount!),
                  palette: palette,
                ),
            ],
          ),
        ),
        if (forumName?.isNotEmpty == true) ...[
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 154),
            child: _TagForumChip(
              key: Key('yamibo-tag-thread-forum-${thread.tid}'),
              label: forumName!,
              palette: palette,
            ),
          ),
        ],
      ],
    );
  }
}

class _TagMetric extends StatelessWidget {
  const _TagMetric({
    super.key,
    required this.icon,
    required this.value,
    required this.semanticsLabel,
    required this.palette,
  });

  final IconData icon;
  final int value;
  final String semanticsLabel;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfaceContainerHigh.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: palette.softText),
                  const SizedBox(width: 4),
                  Text(
                    value.toString(),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.softText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagForumChip extends StatelessWidget {
  const _TagForumChip({super.key, required this.label, required this.palette});

  final String label;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: palette.tag,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TagPager extends StatelessWidget {
  const _TagPager({
    required this.data,
    required this.capabilities,
    required this.isLoading,
    required this.palette,
    required this.onSelectPage,
  });

  final ForumTagDirectoryData data;
  final ForumTagDirectoryReadCapabilities? capabilities;
  final bool isLoading;
  final ForumDisplayThemePalette palette;
  final ValueChanged<int> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final currentPage = data.pagination.currentPage;
    final lastPage = data.pagination.totalPages;
    final supportsDirection =
        capabilities?.supports(
          ForumTagDirectoryCapability.directionalPagination,
        ) ==
        true;
    final canLoadPrevious =
        supportsDirection && data.pagination.hasPrevious == true;
    final hasMore = supportsDirection && data.pagination.hasNext == true;
    final hasPageChoices = lastPage != null && lastPage > 1;
    if (!canLoadPrevious && !hasMore && !hasPageChoices && !isLoading) {
      return const SizedBox(height: 8);
    }
    return Padding(
      key: const Key('yamibo-tag-pager'),
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton(
            key: const Key('yamibo-tag-previous-page-button'),
            onPressed: !canLoadPrevious || isLoading
                ? null
                : () => onSelectPage(currentPage - 1),
            style: _tagPageButtonStyle(context, palette),
            child: Text(AppLocalizations.of(context).commonPreviousPage),
          ),
          NativePageDropdownButton(
            buttonKey: const Key('yamibo-tag-current-page-button'),
            menuKeyPrefix: 'yamibo-tag',
            currentPage: currentPage,
            lastPage: lastPage,
            hasMore: hasMore,
            enabled: !isLoading,
            label: AppLocalizations.of(context).commonPage(currentPage),
            style: _tagPageButtonStyle(context, palette),
            onSelected: onSelectPage,
          ),
          if (isLoading)
            const SizedBox(
              width: 64,
              height: 34,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              key: const Key('yamibo-tag-next-page-button'),
              onPressed: !hasMore ? null : () => onSelectPage(currentPage + 1),
              style: _tagPageButtonStyle(context, palette),
              child: Text(AppLocalizations.of(context).commonNextPage),
            ),
        ],
      ),
    );
  }
}

ButtonStyle _tagPageButtonStyle(
  BuildContext context,
  ForumDisplayThemePalette palette,
) {
  return TextButton.styleFrom(
    backgroundColor: palette.surfaceContainerHigh.withValues(alpha: 0.42),
    disabledBackgroundColor: palette.surfaceContainerHigh.withValues(
      alpha: 0.42,
    ),
    foregroundColor: palette.muted,
    disabledForegroundColor: palette.disabledText,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    minimumSize: const Size(0, 34),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.palette});

  final String message;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.warning.withValues(alpha: 0.08),
          palette.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: palette.warning,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyTagThreadList extends StatelessWidget {
  const _EmptyTagThreadList({required this.palette});

  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('yamibo-tag-empty'),
      decoration: _tagSurfaceDecoration(palette),
      child: Material(
        color: palette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            AppLocalizations.of(context).tagEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TagPageErrorView extends StatelessWidget {
  const _TagPageErrorView({
    required this.message,
    required this.onRetry,
    required this.palette,
  });

  final String message;
  final VoidCallback onRetry;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DecoratedBox(
          decoration: _tagSurfaceDecoration(palette),
          child: Material(
            color: palette.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    key: const Key('yamibo-tag-retry-button'),
                    onPressed: onRetry,
                    child: Text(AppLocalizations.of(context).commonRetry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _tagSurfaceDecoration(ForumDisplayThemePalette palette) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
  );
}
