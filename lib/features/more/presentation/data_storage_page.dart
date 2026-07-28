import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/more/presentation/data_storage_debug_actions.dart';
import 'package:y300/features/more/presentation/data_storage_debug_overview.dart';
import 'package:y300/features/more/presentation/data_storage_formatters.dart';
import 'package:y300/features/more/presentation/more_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class DataStoragePage extends ConsumerWidget {
  const DataStoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dataStorageControllerProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.moreStorageTitle)),
      body: state.when(
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
              const Divider(height: 32),
              ListTile(
                key: const Key('data-storage-effective-directory'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l10n.moreStorageLocation,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(viewState.storagePath),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('data-storage-default-directory'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.moreStorageDefaultLocation),
                subtitle: Text(viewState.defaultStoragePath),
              ),
              if (viewState.customStoragePath != null) ...[
                const SizedBox(height: 8),
                ListTile(
                  key: const Key('data-storage-custom-directory'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.moreStorageCustomLocation),
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
                label: Text(l10n.moreStorageChooseDirectory),
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
                label: Text(l10n.moreStorageRestoreDefault),
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
