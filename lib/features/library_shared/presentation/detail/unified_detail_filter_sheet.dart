import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/l10n/app_localizations.dart';

class UnifiedDetailChapterToolbar extends StatelessWidget {
  const UnifiedDetailChapterToolbar({
    super.key,
    required this.chapterCount,
    required this.filterSummary,
    required this.hasActiveFilter,
    this.modeControl,
  });

  final int chapterCount;
  final String filterSummary;
  final bool hasActiveFilter;
  final Widget? modeControl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('unified-detail-chapter-toolbar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.libraryChapterCount(chapterCount),
                  key: const Key('unified-detail-chapter-heading'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (modeControl != null) ...[
                const SizedBox(width: 12),
                modeControl!,
              ],
            ],
          ),
          if (hasActiveFilter) ...[
            const SizedBox(height: 6),
            Text(
              filterSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class UnifiedDetailTriStateLine extends StatelessWidget {
  const UnifiedDetailTriStateLine({
    super.key,
    required this.lineKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key lineKey;
  final String label;
  final TriStateFilterValue value;
  final ValueChanged<TriStateFilterValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = switch (value) {
      TriStateFilterValue.ignore => Icons.check_box_outline_blank,
      TriStateFilterValue.include => Icons.check_box,
      TriStateFilterValue.exclude => Icons.indeterminate_check_box,
    };
    final stateLabel = switch (value) {
      TriStateFilterValue.ignore => AppLocalizations.of(
        context,
      ).libraryChapterFilterAny,
      TriStateFilterValue.include => AppLocalizations.of(
        context,
      ).libraryChapterFilterOnly(label),
      TriStateFilterValue.exclude => AppLocalizations.of(
        context,
      ).libraryChapterFilterExclude(label),
    };

    return ListTile(
      key: lineKey,
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        stateLabel,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () {
        final next = switch (value) {
          TriStateFilterValue.ignore => TriStateFilterValue.include,
          TriStateFilterValue.include => TriStateFilterValue.exclude,
          TriStateFilterValue.exclude => TriStateFilterValue.ignore,
        };
        onChanged(next);
      },
    );
  }
}

class UnifiedDetailSheetSectionHeader extends StatelessWidget {
  const UnifiedDetailSheetSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
