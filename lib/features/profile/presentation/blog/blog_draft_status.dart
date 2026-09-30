import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Recovery actions stay separate from the writing surface and remote editor.
class BlogDraftStatus extends StatelessWidget {
  const BlogDraftStatus({
    super.key,
    required this.loadFailed,
    required this.saveFailed,
    required this.pending,
    required this.imagesBlocked,
    required this.verifyingImages,
    required this.onLoadRetry,
    required this.onSaveRetry,
    required this.onImageRetry,
    required this.onCheck,
    required this.onResume,
  });
  final bool loadFailed, saveFailed, pending, imagesBlocked, verifyingImages;
  final VoidCallback onLoadRetry, onSaveRetry, onCheck, onResume;
  final VoidCallback? onImageRetry;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loadFailed) ...[
          Text(l10n.profileBlogDraftLoadFailed),
          TextButton(
            key: const Key('blog-draft-load-retry'),
            onPressed: onLoadRetry,
            child: Text(l10n.commonRetry),
          ),
        ],
        if (saveFailed) ...[
          Text(l10n.profileBlogDraftSaveFailed),
          TextButton(
            key: const Key('blog-draft-save-retry'),
            onPressed: onSaveRetry,
            child: Text(l10n.commonRetry),
          ),
        ],
        if (pending) ...[
          Text(l10n.profileBlogDraftPending),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const Key('blog-draft-check'),
                onPressed: onCheck,
                child: Text(l10n.profileBlogMine),
              ),
              TextButton(
                key: const Key('blog-draft-resume'),
                onPressed: onResume,
                child: Text(l10n.profileBlogDraftResume),
              ),
            ],
          ),
        ],
        if (verifyingImages) Text(l10n.profileBlogDraftImagesChecking),
        if (imagesBlocked && !verifyingImages) ...[
          Text(l10n.profileBlogDraftImagesUnavailable),
          TextButton(
            key: const Key('blog-draft-images-retry'),
            onPressed: onImageRetry,
            child: Text(l10n.commonRetry),
          ),
        ],
      ],
    );
  }
}
