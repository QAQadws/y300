import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_download_state.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/services/app_update_download_service.dart';

class AppUpdateDownloadHost extends ConsumerWidget {
  const AppUpdateDownloadHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(appUpdateDownloadServiceProvider);
    return StreamBuilder<AppUpdateDownloadState>(
      initialData: service.state,
      stream: service.stateStream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const AppUpdateIdle();
        if (state is AppUpdateIdle) {
          return child;
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            child,
            const ModalBarrier(color: Colors.black26, dismissible: false),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.all(16),
                child: AppUpdateDownloadPanel(service: service, state: state),
              ),
            ),
          ],
        );
      },
    );
  }
}

class AppUpdateDownloadPanel extends StatelessWidget {
  const AppUpdateDownloadPanel({
    super.key,
    required this.service,
    required this.state,
  });

  final AppUpdateDownloadService service;
  final AppUpdateDownloadState state;

  @override
  Widget build(BuildContext context) {
    final content = switch (state) {
      AppUpdatePreparing(:final artifact) => _PreparingContent(
        title: '准备下载更新',
        version: artifact.version.toString(),
      ),
      AppUpdateDownloading(
        :final artifact,
        :final progress,
        :final receivedBytes,
        :final totalBytes,
      ) =>
        _DownloadingContent(
          artifact: artifact,
          progress: progress,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          onCancel: () => unawaited(service.cancel()),
        ),
      AppUpdateVerifying(:final artifact) => _PreparingContent(
        title: '正在校验更新',
        version: artifact.version.toString(),
      ),
      AppUpdateReadyToInstall(:final artifact) => _ReadyContent(
        artifact: artifact,
        onInstall: () => unawaited(service.installReady()),
        onClose: () => unawaited(service.reset()),
      ),
      AppUpdateInstalling(:final artifact) => _InstallingContent(
        artifact: artifact,
        onClose: () => unawaited(service.dismiss()),
      ),
      AppUpdateFailed(:final artifact, :final failure) => _FailedContent(
        artifact: artifact,
        failure: failure,
        onRetry: artifact == null ? null : () => unawaited(service.retry()),
        onClose: () => unawaited(service.reset()),
      ),
      AppUpdateIdle() => const SizedBox.shrink(),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: content,
        ),
      ),
    );
  }
}

class _PreparingContent extends StatelessWidget {
  const _PreparingContent({required this.title, required this.version});

  final String title;
  final String version;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('v$version'),
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
      ],
    );
  }
}

class _DownloadingContent extends StatelessWidget {
  const _DownloadingContent({
    required this.artifact,
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
    required this.onCancel,
  });

  final AppUpdateArtifact artifact;
  final double progress;
  final int receivedBytes;
  final int? totalBytes;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final progressText = totalBytes == null
        ? _formatBytes(receivedBytes)
        : '${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes!)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '正在下载 Y300 v${artifact.version}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: totalBytes == null ? null : progress,
          minHeight: 6,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(child: Text(progressText)),
            Text('${(progress * 100).round()}%'),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: const Text('取消'),
          ),
        ),
      ],
    );
  }
}

class _ReadyContent extends StatelessWidget {
  const _ReadyContent({
    required this.artifact,
    required this.onInstall,
    required this.onClose,
  });

  final AppUpdateArtifact artifact;
  final VoidCallback onInstall;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('更新已准备好', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('v${artifact.version} 已通过 SHA-256 校验，可以安装。'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(onPressed: onClose, child: const Text('稍后安装')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onInstall,
              icon: const Icon(Icons.install_mobile),
              label: const Text('安装更新'),
            ),
          ],
        ),
      ],
    );
  }
}

class _InstallingContent extends StatelessWidget {
  const _InstallingContent({required this.artifact, required this.onClose});

  final AppUpdateArtifact artifact;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('已打开系统安装器', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('请在 Android 系统页面确认安装 v${artifact.version}。'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: onClose, child: const Text('返回应用')),
        ),
      ],
    );
  }
}

class _FailedContent extends StatelessWidget {
  const _FailedContent({
    required this.artifact,
    required this.failure,
    required this.onRetry,
    required this.onClose,
  });

  final AppUpdateArtifact? artifact;
  final AppUpdateFailure failure;
  final VoidCallback? onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('更新失败', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(_failureMessage(failure.code)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(onPressed: onClose, child: const Text('关闭')),
            if (retry != null) ...<Widget>[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

String _failureMessage(AppUpdateFailureCode code) {
  return switch (code) {
    AppUpdateFailureCode.apkDownloadCancelled => '下载已取消，可以重新尝试。',
    AppUpdateFailureCode.networkUnavailable => '网络不可用，请检查网络后重试。',
    AppUpdateFailureCode.requestTimeout => '更新下载超时，请稍后重试。',
    AppUpdateFailureCode.checksumRequestFailed ||
    AppUpdateFailureCode.checksumMalformed ||
    AppUpdateFailureCode.checksumFileNameMismatch => '更新校验文件无效，请稍后重试。',
    AppUpdateFailureCode.apkHashMismatch => '下载文件校验失败，已阻止安装。',
    AppUpdateFailureCode.installPermissionRequired => '请允许安装未知来源应用后重试。',
    AppUpdateFailureCode.installerUnavailable => '设备上没有可用的 APK 安装器。',
    _ => '更新处理失败，请稍后重试。',
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
