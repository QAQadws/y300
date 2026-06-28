import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';

/// 表情选择底部面板。
///
/// 该 widget 与具体业务（reply / newthread）解耦，只依赖 composer_shared 自己
/// 的表情 provider。调用方通过 `Navigator.pop(context, sticker)` 拿到选择结果。
class StickerPickerSheet extends ConsumerWidget {
  const StickerPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGroups = ref.watch(stickerGroupsProvider);
    final asyncLastGroupId = ref.watch(stickerPickerLastGroupIdProvider);
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
                  '需要联网加载表情包',
                  key: Key('reply-sticker-picker-empty'),
                  textAlign: TextAlign.center,
                ),
              );
            }
            return asyncLastGroupId.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  key: Key('reply-sticker-picker-loading'),
                ),
              ),
              error: (_, _) => _StickerPickerContent(
                groups: visibleGroups,
                initialGroupId: null,
              ),
              data: (lastGroupId) => _StickerPickerContent(
                groups: visibleGroups,
                initialGroupId: lastGroupId,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StickerPickerContent extends ConsumerStatefulWidget {
  const _StickerPickerContent({
    required this.groups,
    required this.initialGroupId,
  });

  final List<StickerGroup> groups;
  final String? initialGroupId;

  @override
  ConsumerState<_StickerPickerContent> createState() {
    return _StickerPickerContentState();
  }
}

class _StickerPickerContentState extends ConsumerState<_StickerPickerContent> {
  TabController? _tabController;
  int? _lastSavedIndex;

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChanged);
    _tabController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialIndex = _initialIndex();
    return DefaultTabController(
      length: widget.groups.length,
      initialIndex: initialIndex,
      child: Builder(
        builder: (context) {
          _bindTabController(DefaultTabController.of(context));
          return Column(
            children: [
              TabBar(
                isScrollable: true,
                onTap: (index) {
                  if (_saveGroupAt(index)) {
                    _lastSavedIndex = index;
                  }
                },
                tabs: [
                  for (final group in widget.groups)
                    Tab(
                      key: Key('reply-sticker-group-tab-${group.id}'),
                      text: group.title,
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final group in widget.groups)
                      StickerGrid(stickers: group.stickers),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  int _initialIndex() {
    final initialGroupId = widget.initialGroupId;
    if (initialGroupId == null) {
      return 0;
    }
    final index = widget.groups.indexWhere((group) {
      return group.id == initialGroupId;
    });
    return index < 0 ? 0 : index;
  }

  void _bindTabController(TabController controller) {
    if (_tabController == controller) {
      return;
    }
    _tabController?.removeListener(_handleTabChanged);
    _tabController = controller;
    _lastSavedIndex = controller.index;
    controller.addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    final controller = _tabController;
    if (controller == null || controller.indexIsChanging) {
      return;
    }
    final index = controller.index;
    if (index == _lastSavedIndex ||
        index < 0 ||
        index >= widget.groups.length) {
      return;
    }
    if (_saveGroupAt(index)) {
      _lastSavedIndex = index;
    }
  }

  bool _saveGroupAt(int index) {
    if (index < 0 || index >= widget.groups.length) {
      return false;
    }
    final groupId = widget.groups[index].id;
    unawaited(_persistLastGroupId(groupId));
    return true;
  }

  Future<void> _persistLastGroupId(String groupId) async {
    await ref
        .read(stickerPickerPreferencesRepositoryProvider)
        .saveLastGroupId(groupId);
    ref.invalidate(stickerPickerLastGroupIdProvider);
  }
}

class StickerGrid extends StatelessWidget {
  const StickerGrid({super.key, required this.stickers});

  final List<StickerItem> stickers;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 64,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return IconButton(
          key: Key('reply-sticker-item-${sticker.code}'),
          constraints: const BoxConstraints.tightFor(width: 56, height: 56),
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop(sticker);
          },
          icon: CachedLibraryImage(
            request: ForumImageCacheRequests.remoteSmiley(
              url: sticker.imageUrl,
            ),
            width: 48,
            height: 48,
            fit: BoxFit.contain,
            placeholder: const SizedBox.shrink(),
            errorPlaceholder: const Icon(Icons.broken_image_outlined),
          ),
        );
      },
    );
  }
}
