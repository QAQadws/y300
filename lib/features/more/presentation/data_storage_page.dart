import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/more/presentation/data_storage_debug_overview_debug.dart'
    if (dart.vm.product) 'package:y300/features/more/presentation/data_storage_debug_overview_stub.dart'
    if (dart.vm.profile) 'package:y300/features/more/presentation/data_storage_debug_overview_stub.dart';
import 'package:y300/features/more/presentation/data_storage_formatters.dart';

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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('data-storage-reload-usage-button'),
                      onPressed: viewState.isUpdating
                          ? null
                          : () => ref
                                .read(dataStorageControllerProvider.notifier)
                                .reloadUsage(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新统计'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('data-storage-export-diagnostics-button'),
                      onPressed: viewState.isUpdating
                          ? null
                          : () => ref
                                .read(dataStorageControllerProvider.notifier)
                                .exportCacheDiagnostics(),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('缓存诊断导出'),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              ListTile(
                key: const Key('data-storage-cache-usage'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '清理缓存',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                trailing: FilledButton(
                  key: const Key('data-storage-clear-cache-button'),
                  onPressed: viewState.isUpdating
                      ? null
                      : () => ref
                            .read(dataStorageControllerProvider.notifier)
                            .clearCache(),
                  child: const Text('清理'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '总计：${formatDataStorageBytes(viewState.usageReport.totalBytes)}',
                key: const Key('data-storage-usage-total'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              buildDataStorageDebugOverview(viewState.usageReport),
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
                          .updateImageCacheMaxBytes(
                            value.round() * 1024 * 1024,
                          ),
              ),
              Text(
                '清理页面缓存（帖子列表/详情）与漫画页、帖子图片缓存；封面、头像、表情、已下载内容不会被清除。',
                key: const Key('data-storage-cache-hint'),
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
                    : () => ref
                          .read(dataStorageControllerProvider.notifier)
                          .chooseStorageDirectory(),
                icon: const Icon(Icons.folder_open),
                label: const Text('选择自定义目录'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('data-storage-restore-default-button'),
                onPressed:
                    viewState.isUpdating || viewState.customStoragePath == null
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
