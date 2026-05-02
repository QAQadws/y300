import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/more/presentation/cache_settings_controller.dart';

class CacheSettingsPage extends ConsumerWidget {
  const CacheSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cacheSettingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('缓存目录设置')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('加载缓存设置失败：$error', textAlign: TextAlign.center),
          ),
        ),
        data: (viewState) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                key: const Key('cache-settings-effective-directory'),
                contentPadding: EdgeInsets.zero,
                title: const Text('当前生效目录'),
                subtitle: Text(viewState.effectiveDirectory),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('cache-settings-default-directory'),
                contentPadding: EdgeInsets.zero,
                title: const Text('默认目录'),
                subtitle: Text(viewState.defaultDirectory),
              ),
              if (viewState.customDirectory != null) ...[
                const SizedBox(height: 8),
                ListTile(
                  key: const Key('cache-settings-custom-directory'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自定义目录'),
                  subtitle: Text(viewState.customDirectory!),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('cache-settings-choose-directory-button'),
                onPressed: viewState.isUpdating
                    ? null
                    : () => ref.read(cacheSettingsControllerProvider.notifier).chooseCustomDirectory(),
                icon: const Icon(Icons.folder_open),
                label: const Text('选择自定义目录'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('cache-settings-restore-default-button'),
                onPressed: viewState.isUpdating || viewState.customDirectory == null
                    ? null
                    : () => ref.read(cacheSettingsControllerProvider.notifier).restoreDefaultDirectory(),
                icon: const Icon(Icons.restore),
                label: const Text('恢复默认目录'),
              ),
              if (viewState.hint != null) ...[
                const SizedBox(height: 12),
                Text(
                  viewState.hint!,
                  key: const Key('cache-settings-hint-text'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
