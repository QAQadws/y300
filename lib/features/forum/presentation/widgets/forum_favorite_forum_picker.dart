import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
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

  final Future<ApiResult<List<FavoriteForum>>> Function() loadFavoriteForums;
  final Future<ApiResult<ForumFavoriteMutationResult>> Function(
    FavoriteForum forum,
  )
  onUnfavorite;
  final FutureOr<void> Function(
    FavoriteForum forum,
    ForumFavoriteMutationResult result,
  )?
  onSuccess;

  @override
  State<ForumFavoriteForumPicker> createState() =>
      _ForumFavoriteForumPickerState();
}

class _ForumFavoriteForumPickerState extends State<ForumFavoriteForumPicker> {
  late Future<ApiResult<List<FavoriteForum>>> _future;
  String? _submittingFavid;

  @override
  void initState() {
    super.initState();
    _future = widget.loadFavoriteForums();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        key: const Key('forum-favorite-forum-picker'),
        height: 360,
        child: FutureBuilder<ApiResult<List<FavoriteForum>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
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
              success: (forums) {
                if (forums.isEmpty) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context).forumNoFavoriteForums,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        AppLocalizations.of(context).forumFavoriteForumsTitle,
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: forums.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final forum = forums[index];
                          final isSubmitting = _submittingFavid == forum.favid;
                          return ListTile(
                            key: Key(
                              'forum-favorite-forum-item-${forum.favid}',
                            ),
                            enabled: _submittingFavid == null,
                            title: Text(forum.title),
                            subtitle: Text(
                              AppLocalizations.of(
                                context,
                              ).forumForumByFid(forum.fid),
                            ),
                            trailing: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            onTap: _submittingFavid == null
                                ? () => _handleUnfavorite(forum)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              failure: (error) => _ForumFavoriteForumPickerErrorView(
                message: ForumTextResolver.favoriteForumsLoadFailure(
                  AppLocalizations.of(context),
                  error.message,
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

  Future<void> _handleUnfavorite(FavoriteForum forum) async {
    setState(() {
      _submittingFavid = forum.favid;
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
      _submittingFavid = null;
    });
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
            const SizedBox(height: 12),
            FilledButton(
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
