import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/more/presentation/data_storage_formatters.dart';
import 'package:y300/features/more/presentation/more_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

Widget buildDataStorageDebugOverview(
  StorageUsageReport report,
  AppLocalizations l10n,
) {
  if (!kDebugMode) {
    return const SizedBox.shrink();
  }
  return _StorageUsageOverview(report: report, l10n: l10n);
}

class _StorageUsageOverview extends StatelessWidget {
  const _StorageUsageOverview({required this.report, required this.l10n});

  final StorageUsageReport report;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('data-storage-usage-overview'),
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      title: Text(
        l10n.moreStorageUsageOverview,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      subtitle: Text(
        l10n.moreStorageUsageTotal(formatDataStorageBytes(report.totalBytes)),
      ),
      children: [
        const SizedBox(height: 4),
        for (final section in report.sections) ...[
          _StorageUsageSectionTile(section: section, l10n: l10n),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _StorageUsageSectionTile extends StatelessWidget {
  const _StorageUsageSectionTile({required this.section, required this.l10n});

  final StorageUsageSection section;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: Key('data-storage-usage-section-${section.bucket.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                MoreTextResolver.storageLabel(l10n, section.labelRef),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              formatDataStorageBytes(section.bytes),
              style: textTheme.bodyMedium,
            ),
          ],
        ),
        if (section.slices.isNotEmpty || section.categories.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (final category in section.categories)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                key: Key('data-storage-image-cache-category-${category.id}'),
                children: [
                  Expanded(
                    child: Text(
                      MoreTextResolver.storageLabel(l10n, category.labelRef),
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatDataStorageBytes(category.bytes),
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          for (final slice in section.slices.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      MoreTextResolver.storageLabel(l10n, slice.labelRef),
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    slice.bytes > 0 ? formatDataStorageBytes(slice.bytes) : '',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
