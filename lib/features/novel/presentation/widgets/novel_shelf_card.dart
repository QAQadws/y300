import 'package:flutter/material.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/novel_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';

class NovelShelfCard extends StatelessWidget {
  const NovelShelfCard({super.key, required this.item, required this.onTap});

  final NovelItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ShelfCoverCard(
      key: ValueKey<String>('novel-card-${item.novelId}'),
      title: NovelTextResolver.workTitle(l10n, item.title, item.novelId),
      coverImageUrl: item.coverImageUrl,
      onTap: onTap,
      topLeftBadge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          l10n.novelOriginalBadge,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}
