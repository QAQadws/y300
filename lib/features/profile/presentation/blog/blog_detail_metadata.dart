import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';

class BlogDetailMetadata extends StatelessWidget {
  const BlogDetailMetadata({
    super.key,
    required this.date,
    required this.categories,
  });

  final String date;
  final List<BlogDetailCategoryLink> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.y300NativeContent.soft,
      height: 1.1,
    );
    return Wrap(
      key: categories.isNotEmpty ? const Key('blog-detail-categories') : null,
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (date.isNotEmpty)
          Text(
            date,
            key: const Key('blog-detail-date'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dateStyle,
          ),
        for (final (index, category) in categories.indexed)
          // Keep the separator with its link when the category wraps.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (date.isNotEmpty || index > 0) ...[
                ExcludeSemantics(child: Text('·', style: dateStyle)),
                const SizedBox(width: 4),
              ],
              Flexible(child: category),
            ],
          ),
      ],
    );
  }
}

class BlogDetailCategoryLink extends StatelessWidget {
  const BlogDetailCategoryLink({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.y300NativeContent.accent;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, size: 12, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
