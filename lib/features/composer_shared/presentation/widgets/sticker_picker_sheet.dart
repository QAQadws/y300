import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_group_panel.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_error_summary.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 表情选择底部面板。
///
/// 该 widget 与具体业务（reply / newthread）解耦，只依赖 composer_shared 自己
/// 的表情 provider。调用方通过 `Navigator.pop(context, sticker)` 拿到选择结果。
class StickerPickerSheet extends ConsumerWidget {
  const StickerPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final asyncGroups = ref.watch(stickerGroupsProvider);
    final asyncLastGroupId = ref.watch(
      stickerPickerLastGroupIdControllerProvider,
    );
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
                l10n.composerStickerLoadFailed(
                  ComposerErrorSummary.sanitize(error) ??
                      l10n.composerUnknownFailure('other'),
                ),
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
              return Center(
                child: Text(
                  l10n.composerStickerNetworkRequired,
                  key: const Key('reply-sticker-picker-empty'),
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
              error: (_, _) => ComposerStickerGroupPanel(
                keyPrefix: 'reply',
                groups: visibleGroups,
                initialGroupId: null,
                onGroupChanged: (groupId) {
                  unawaited(
                    ref
                        .read(
                          stickerPickerLastGroupIdControllerProvider.notifier,
                        )
                        .selectGroup(groupId),
                  );
                },
                onSelected: (sticker) => Navigator.of(context).pop(sticker),
              ),
              data: (lastGroupId) => ComposerStickerGroupPanel(
                keyPrefix: 'reply',
                groups: visibleGroups,
                initialGroupId: lastGroupId,
                onGroupChanged: (groupId) {
                  unawaited(
                    ref
                        .read(
                          stickerPickerLastGroupIdControllerProvider.notifier,
                        )
                        .selectGroup(groupId),
                  );
                },
                onSelected: (sticker) => Navigator.of(context).pop(sticker),
              ),
            );
          },
        ),
      ),
    );
  }
}
