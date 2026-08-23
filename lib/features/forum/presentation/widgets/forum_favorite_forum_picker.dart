import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/forum/presentation/forum_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class ForumFavoriteForumPicker extends StatefulWidget {
  const ForumFavoriteForumPicker({
    super.key,
    required this.loadFavoriteForums,
    required this.onUnfavorite,
    this.onSuccess,
  });

  final Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  Function()
  loadFavoriteForums;
  final Future<ApiResult<ForumFavoriteMutationResult>> Function(
    FavoriteForumEntry forum,
  )
  onUnfavorite;
  final FutureOr<void> Function(
    FavoriteForumEntry forum,
    ForumFavoriteMutationResult result,
  )?
  onSuccess;

  @override
  State<ForumFavoriteForumPicker> createState() =>
      _ForumFavoriteForumPickerState();
}

class _ForumFavoriteForumPickerState extends State<ForumFavoriteForumPicker> {
  late Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  _future;
  String? _submittingRemoteFavoriteId;

  @override
  void initState() {
    super.initState();
    _future = widget.loadFavoriteForums();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('forum-favorite-forum-picker'),
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child:
            FutureBuilder<
              DataReadResult<
                FavoriteForumDirectoryData,
                FavoriteForumDirectoryReadCapabilities
              >
            >(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _ForumFavoriteForumPickerFrame(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final result = snapshot.data;
                if (result == null) {
                  return _ForumFavoriteForumPickerErrorView(
                    message: ForumTextResolver.favoriteForumsLoadFailure(
                      AppLocalizations.of(context),
                      null,
                    ),
                    onRetry: _reload,
                  );
                }

                return result.when(
                  success: (data, capabilities, _) {
                    final forums = data.items;
                    if (forums.isEmpty) {
                      return _ForumFavoriteForumPickerFrame(
                        body: _ForumFavoriteForumPickerEmptyView(
                          message: AppLocalizations.of(
                            context,
                          ).forumNoFavoriteForums,
                        ),
                      );
                    }
                    return _ForumFavoriteForumPickerFrame(
                      itemCount: forums.length,
                      body: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: forums.length,
                        separatorBuilder: (context, _) => Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        itemBuilder: (context, index) {
                          final forum = forums[index];
                          final remoteFavoriteId = forum.remoteFavoriteId;
                          final canUnfavorite =
                              capabilities.supports(
                                FavoriteForumDirectoryCapability
                                    .stableRemoteFavoriteIdentity,
                              ) &&
                              remoteFavoriteId?.trim().isNotEmpty == true;
                          final isSubmitting =
                              _submittingRemoteFavoriteId == remoteFavoriteId;
                          return _ForumFavoriteForumRow(
                            forum: forum,
                            isSubmitting: isSubmitting,
                            enabled:
                                canUnfavorite &&
                                _submittingRemoteFavoriteId == null,
                            onTap: () => _handleUnfavorite(forum),
                          );
                        },
                      ),
                    );
                  },
                  failure: (failure) => _ForumFavoriteForumPickerErrorView(
                    message: ForumTextResolver.favoriteForumsLoadFailure(
                      AppLocalizations.of(context),
                      failure.diagnosticMessage,
                    ),
                    onRetry: _reload,
                  ),
                );
              },
            ),
      ),
    );
  }

  void _reload() {
    setState(() {
      _future = widget.loadFavoriteForums();
    });
  }

  Future<void> _handleUnfavorite(FavoriteForumEntry forum) async {
    final remoteFavoriteId = forum.remoteFavoriteId?.trim();
    if (remoteFavoriteId == null || remoteFavoriteId.isEmpty) {
      return;
    }
    setState(() {
      _submittingRemoteFavoriteId = remoteFavoriteId;
    });
    final result = await widget.onUnfavorite(forum);
    if (!mounted) {
      return;
    }
    if (result case ApiSuccess<ForumFavoriteMutationResult>(:final data)) {
      Navigator.of(context).pop();
      await widget.onSuccess?.call(forum, data);
      return;
    }

    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ForumTextResolver.favoriteActionFailure(
              AppLocalizations.of(context),
              result.errorOrNull?.message,
            ),
          ),
        ),
      );
    setState(() {
      _submittingRemoteFavoriteId = null;
    });
  }
}

class _ForumFavoriteForumPickerFrame extends StatelessWidget {
  const _ForumFavoriteForumPickerFrame({
    required this.body,
    this.itemCount = 0,
  });

  final Widget body;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maximumHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.72,
      520.0,
    );
    final minimumHeight = math.min(200.0, maximumHeight);
    final preferredHeight = itemCount == 0 ? 220.0 : 68.0 + itemCount * 64.0;
    final height = preferredHeight
        .clamp(minimumHeight, maximumHeight)
        .toDouble();

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            key: const Key('forum-favorite-forum-picker-header'),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.forumFavoriteForumsTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _ForumFavoriteForumRow extends StatelessWidget {
  const _ForumFavoriteForumRow({
    required this.forum,
    required this.isSubmitting,
    required this.enabled,
    required this.onTap,
  });

  final FavoriteForumEntry forum;
  final bool isSubmitting;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final title = forum.title.trim().isEmpty
        ? '#${forum.fid.trim()}'
        : forum.title.trim();
    final description = forum.description?.trim() ?? '';

    return ListTile(
      key: Key(
        'forum-favorite-forum-item-${forum.remoteFavoriteId ?? forum.fid}',
      ),
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: description.isEmpty
          ? null
          : Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
      trailing: isSubmitting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              key: Key(
                'forum-favorite-forum-remove-'
                '${forum.remoteFavoriteId ?? forum.fid}',
              ),
              onPressed: enabled ? onTap : null,
              tooltip: l10n.forumUnfavoriteForum,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              color: colorScheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
      onTap: enabled ? onTap : null,
    );
  }
}

class _ForumFavoriteForumPickerEmptyView extends StatelessWidget {
  const _ForumFavoriteForumPickerEmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ForumFavoriteForumPickerErrorView extends StatelessWidget {
  const _ForumFavoriteForumPickerErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('forum-favorite-forum-picker-retry'),
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
