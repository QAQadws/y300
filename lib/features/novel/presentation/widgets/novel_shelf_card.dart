import 'package:flutter/material.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';

class NovelShelfCard extends StatelessWidget {
  const NovelShelfCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final NovelItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey<String>('novel-card-${item.novelId}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.coverImageUrl != null)
              Image.network(
                item.coverImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildNoCoverCard(context),
              )
            else
              _buildNoCoverCard(context),
            _buildGradientOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildNoCoverCard(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3B5B7C),
            Color(0xFF6A7FA0),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              '原创',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGradientOverlay(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x00000000),
              Color(0xA6000000),
              Color(0xCC000000),
            ],
          ),
        ),
        child: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
