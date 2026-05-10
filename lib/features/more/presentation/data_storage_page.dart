import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';

class DataStoragePage extends ConsumerWidget {
  const DataStoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dataStorageControllerProvider);

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
                key: const Key('data-storage-image-cache-usage'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '清除图片缓存',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                subtitle: Text('已使用：${formatDataStorageBytes(viewState.imageCacheUsageBytes)}'),
                trailing: FilledButton(
                  key: const Key('data-storage-clear-image-cache-button'),
                  onPressed: viewState.isUpdating
                      ? null
                      : () => ref.read(dataStorageControllerProvider.notifier).clearImageCache(),
                  child: const Text('清除'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '最大缓存：$maxMb MB',
                key: const Key('data-storage-image-cache-max-label'),
              ),
              Slider(
                key: const Key('data-storage-image-cache-max-slider'),
                value: maxMb.toDouble().clamp(128.0, 2048.0).toDouble(),
                min: 128,
                max: 2048,
                divisions: 15,
                label: '$maxMb MB',
                onChanged: viewState.isUpdating
                    ? null
                    : (value) => ref
                        .read(dataStorageControllerProvider.notifier)
                        .updateImageCacheMaxBytes(value.round() * 1024 * 1024),
              ),
              Text(
                '封面、作品信息、标签和阅读状态不会被清除；建议不要频繁清理缓存。',
                key: const Key('data-storage-image-cache-hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 32),
              ListTile(
                key: const Key('data-storage-effective-directory'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '存储位置',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(viewState.storagePath),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('data-storage-default-directory'),
                contentPadding: EdgeInsets.zero,
                title: const Text('默认位置'),
                subtitle: Text(viewState.defaultStoragePath),
              ),
              if (viewState.customStoragePath != null) ...[
                const SizedBox(height: 8),
                ListTile(
                  key: const Key('data-storage-custom-directory'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自定义位置'),
                  subtitle: Text(viewState.customStoragePath!),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('data-storage-choose-directory-button'),
                onPressed: viewState.isUpdating
                    ? null
                    : () => ref.read(dataStorageControllerProvider.notifier).chooseStorageDirectory(),
                icon: const Icon(Icons.folder_open),
                label: const Text('选择自定义目录'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('data-storage-restore-default-button'),
                onPressed: viewState.isUpdating || viewState.customStoragePath == null
                    ? null
                    : () => ref
                        .read(dataStorageControllerProvider.notifier)
                        .restoreDefaultStorageDirectory(),
                icon: const Icon(Icons.restore),
                label: const Text('恢复默认'),
              ),
              if (viewState.hint != null) ...[
                const SizedBox(height: 12),
                Text(
                  viewState.hint!,
                  key: const Key('data-storage-hint-text'),
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

String formatDataStorageBytes(int bytes) {
  final normalized = bytes < 0 ? 0 : bytes;
  final kb = normalized / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}
