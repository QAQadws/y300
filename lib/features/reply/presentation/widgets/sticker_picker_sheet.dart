import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

class StickerPickerSheet extends ConsumerWidget {
  const StickerPickerSheet({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGroups = ref.watch(stickerGroupsProvider);
    return SafeArea(
      top: false,
      child: SizedBox(
        key: const Key('reply-sticker-picker-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.48,
        child: asyncGroups.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              key: Key('reply-sticker-picker-loading'),
            ),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '表情加载失败：$error',
                key: const Key('reply-sticker-picker-error'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (groups) {
            final visibleGroups = groups
                .where((group) => group.stickers.isNotEmpty)
                .toList(growable: false);
            if (visibleGroups.isEmpty) {
              return const Center(
                child: Text(
                  '',
                  key: Key('reply-sticker-picker-empty'),
                ),
              );
            }
            return DefaultTabController(
              length: visibleGroups.length,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabs: [
                      for (final group in visibleGroups)
                        Tab(
                          key: Key('reply-sticker-group-tab-${group.id}'),
                          text: group.title,
                        ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (final group in visibleGroups)
                          StickerGrid(stickers: group.stickers),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class StickerGrid extends StatelessWidget {
  const StickerGrid({
    super.key,
    required this.stickers,
  });

  final List<StickerItem> stickers;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 56,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return IconButton(
          key: Key('reply-sticker-item-${sticker.code}'),
          tooltip: sticker.code,
          onPressed: () {
            Navigator.of(context).pop(sticker);
          },
          icon: Image.asset(
            sticker.assetPath,
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Text(
              sticker.code,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}
