import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/more/presentation/data_storage_debug_actions.dart';
import 'package:y300/features/more/presentation/data_storage_debug_overview.dart';
import 'package:y300/features/more/presentation/data_storage_formatters.dart';
import 'package:y300/features/more/presentation/more_text_resolver.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';
import 'package:y300/features/storage/presentation/storage_root_migration_controller.dart';
import 'package:y300/l10n/app_localizations.dart';

class DataStoragePage extends ConsumerWidget {
  const DataStoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dataStorageControllerProvider);
    final migration = ref.watch(storageRootMigrationControllerProvider);
    final pathPreview = ref.watch(dataStoragePathPreviewProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.moreStorageTitle)),
      body: migration.when(
        loading: () =>
            _StorageMigrationOnlyView(pathPreview: pathPreview, l10n: l10n),
        error: (_, _) => _StorageMigrationOnlyView(
          pathPreview: pathPreview,
          l10n: l10n,
          failureCode: StorageRootMigrationFailureCode.unknown,
          onRetry: () =>
              ref.read(storageRootMigrationControllerProvider.notifier).retry(),
        ),
        data: (migrationResult) => state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.moreStorageLoadFailed('$error'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (viewState) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (migrationResult.status.phase ==
                        StorageRootMigrationPhase.blocked ||
                    migrationResult.status.phase ==
                        StorageRootMigrationPhase.cleanupPending) ...[
                  _StorageMigrationStatusCard(
                    status: migrationResult.status,
                    currentPath:
                        migrationResult.status.phase ==
                            StorageRootMigrationPhase.blocked
                        ? viewState.customStoragePath
                        : null,
                    targetPath:
                        migrationResult.status.phase ==
                            StorageRootMigrationPhase.blocked
                        ? viewState.defaultStoragePath
                        : null,
                    retrying: false,
                    onRetry: () => ref
                        .read(storageRootMigrationControllerProvider.notifier)
                        .retry(),
                  ),
                  const SizedBox(height: 16),
                ],
                ...buildDataStorageDebugActionWidgets(
                  enabled: !viewState.isUpdating,
                  l10n: l10n,
                  onReloadUsage: () => ref
                      .read(dataStorageControllerProvider.notifier)
                      .reloadUsage(),
                  onExportDiagnostics: () => ref
                      .read(dataStorageControllerProvider.notifier)
                      .exportCacheDiagnostics(),
                ),
                ListTile(
                  key: const Key('data-storage-cache-usage'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.moreStorageClearCache,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  trailing: FilledButton(
                    key: const Key('data-storage-clear-cache-button'),
                    onPressed: viewState.isUpdating
                        ? null
                        : () => ref
                              .read(dataStorageControllerProvider.notifier)
                              .clearCache(),
                    child: Text(l10n.moreStorageClear),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatDataStorageBytes(viewState.clearableCacheBytes),
                  key: const Key('data-storage-clearable-cache-size'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                buildDataStorageDebugOverview(viewState.usageReport, l10n),
                const SizedBox(height: 8),
                _CacheLimitControl(
                  valueBytes: viewState.cacheMaxBytes,
                  enabled: !viewState.isUpdating,
                  onCommit: (bytes) => ref
                      .read(dataStorageControllerProvider.notifier)
                      .updateCacheMaxBytes(bytes),
                ),
                Text(
                  l10n.moreStorageCacheDescription,
                  key: const Key('data-storage-cache-hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (viewState.notice != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    MoreTextResolver.storageNotice(l10n, viewState.notice!),
                    key: const Key('data-storage-hint-text'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StorageMigrationOnlyView extends StatelessWidget {
  const _StorageMigrationOnlyView({
    required this.pathPreview,
    required this.l10n,
    this.failureCode,
    this.onRetry,
  });

  final AsyncValue<DataStoragePathPreview> pathPreview;
  final AppLocalizations l10n;
  final StorageRootMigrationFailureCode? failureCode;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final paths = pathPreview.value;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StorageMigrationStatusCard(
          status: StorageRootMigrationStatus(
            phase: failureCode == null
                ? StorageRootMigrationPhase.copying
                : StorageRootMigrationPhase.blocked,
            failureCode: failureCode,
            blocksStorageAccess: true,
          ),
          currentPath: paths?.customStoragePath,
          targetPath: paths?.defaultStoragePath,
          retrying: failureCode == null,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

class _StorageMigrationStatusCard extends StatelessWidget {
  const _StorageMigrationStatusCard({
    required this.status,
    required this.currentPath,
    required this.targetPath,
    required this.retrying,
    required this.onRetry,
  });

  final StorageRootMigrationStatus status;
  final String? currentPath;
  final String? targetPath;
  final bool retrying;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cleanup = status.phase == StorageRootMigrationPhase.cleanupPending;
    final blocked = status.phase == StorageRootMigrationPhase.blocked;
    final message = cleanup
        ? l10n.moreStorageMigrationCleanupPending
        : blocked
        ? MoreTextResolver.storageMigrationFailure(l10n, status.failureCode)
        : l10n.moreStorageMigrationInProgress;
    return Card(
      key: const Key('data-storage-migration-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.moreStorageMigrationTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(message),
            if (!cleanup) ...[
              const SizedBox(height: 6),
              Text(
                l10n.moreStorageMigrationDataSafe,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (currentPath != null && currentPath!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.moreStorageCustomLocation),
              SelectableText(currentPath!),
            ],
            if (targetPath != null && targetPath!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.moreStorageDefaultLocation),
              SelectableText(targetPath!),
            ],
            if (retrying) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(
                key: Key('data-storage-migration-progress'),
              ),
            ] else if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('data-storage-migration-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.moreStorageMigrationRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CacheLimitControl extends StatefulWidget {
  const _CacheLimitControl({
    required this.valueBytes,
    required this.enabled,
    required this.onCommit,
  });

  static const int _megabyte = 1024 * 1024;
  static const double _minMb = 128;
  static const double _maxMb = 2048;

  final int valueBytes;
  final bool enabled;
  final ValueChanged<int> onCommit;

  @override
  State<_CacheLimitControl> createState() => _CacheLimitControlState();
}

class _CacheLimitControlState extends State<_CacheLimitControl> {
  late double _valueMb;
  late int _committedMb;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _syncFromBytes(widget.valueBytes);
  }

  @override
  void didUpdateWidget(_CacheLimitControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _dragging = false;
    }
    if (!_dragging && oldWidget.valueBytes != widget.valueBytes) {
      _syncFromBytes(widget.valueBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valueMb = _valueMb.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).moreStorageMaximumCache('$valueMb MB'),
          key: const Key('data-storage-cache-max-label'),
        ),
        Slider(
          key: const Key('data-storage-cache-max-slider'),
          value: _valueMb,
          min: _CacheLimitControl._minMb,
          max: _CacheLimitControl._maxMb,
          divisions: 15,
          label: '$valueMb MB',
          onChangeStart: widget.enabled ? (_) => _dragging = true : null,
          onChanged: widget.enabled
              ? (value) => setState(() => _valueMb = value)
              : null,
          onChangeEnd: widget.enabled ? _commit : null,
        ),
      ],
    );
  }

  void _commit(double value) {
    _dragging = false;
    final nextMb = value.round();
    if (nextMb == _committedMb) {
      return;
    }
    _committedMb = nextMb;
    widget.onCommit(nextMb * _CacheLimitControl._megabyte);
  }

  void _syncFromBytes(int bytes) {
    final megabytes = (bytes / _CacheLimitControl._megabyte)
        .round()
        .toDouble()
        .clamp(_CacheLimitControl._minMb, _CacheLimitControl._maxMb)
        .toDouble();
    _valueMb = megabytes;
    _committedMb = megabytes.round();
  }
}
