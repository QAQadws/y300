import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/more/presentation/cache_settings_controller.dart';

class CacheSettingsPage extends ConsumerWidget {
  const CacheSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cacheSettingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('数据与存储')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('加载数据与存储设置失败：$error', textAlign: TextAlign.center),
          ),
        ),
        data: (viewState) {
          final maxMb = (viewState.imageCacheMaxBytes / (1024 * 1024)).round();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                key: const Key('cache-settings-image-cache-usage'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '清除图片缓存',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                subtitle: Text('已使用：${_formatBytes(viewState.imageCacheUsageBytes)}'),
                trailing: FilledButton(
                  key: const Key('cache-settings-clear-image-cache-button'),
                  onPressed: viewState.isUpdating
                      ? null
                      : () => ref.read(cacheSettingsControllerProvider.notifier).clearImageCache(),
                  child: const Text('清除'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '最大缓存：$maxMb MB',
                key: const Key('cache-settings-image-cache-max-label'),
              ),
              Slider(
                key: const Key('cache-settings-image-cache-max-slider'),
                value: maxMb.toDouble().clamp(128, 2048),
                min: 128,
                max: 2048,
                divisions: 15,
                label: '$maxMb MB',
                onChanged: viewState.isUpdating
                    ? null
                    : (value) {
                        ref
                            .read(cacheSettingsControllerProvider.notifier)
                            .updateImageCacheMaxBytes(value.round() * 1024 * 1024);
                      },
              ),
              Text(
                '封面、作品信息、标签和阅读状态不会被清除；频繁清理会增加重新加载图片的等待时间。',
                key: const Key('cache-settings-image-cache-hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 32),
              ListTile(
                key: const Key('cache-settings-effective-directory'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '存储位置',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(viewState.effectiveDirectory),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('cache-settings-default-directory'),
                contentPadding: EdgeInsets.zero,
                title: const Text('默认位置'),
                subtitle: Text(viewState.defaultDirectory),
              ),
              if (viewState.customDirectory != null) ...[
                const SizedBox(height: 8),
                ListTile(
                  key: const Key('cache-settings-custom-directory'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自定义位置'),
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
                label: const Text('恢复默认'),
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

  String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(1)} KB';
  }
}
