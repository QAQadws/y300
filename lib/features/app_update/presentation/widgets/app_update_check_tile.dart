import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_update_check_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/presentation/app_update_feedback_messages.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

class AppUpdateCheckTile extends ConsumerStatefulWidget {
  const AppUpdateCheckTile({super.key});

  @override
  ConsumerState<AppUpdateCheckTile> createState() => _AppUpdateCheckTileState();
}

class _AppUpdateCheckTileState extends ConsumerState<AppUpdateCheckTile> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final coordinator = ref.watch(appUpdatePromptCoordinatorProvider);
    return StreamBuilder<String?>(
      initialData: coordinator.installedVersion,
      stream: coordinator.installedVersionStream,
      builder: (context, snapshot) {
        final version = snapshot.data?.trim();
        return ListTile(
          key: const Key('more-check-update-entry'),
          leading: const Icon(Icons.system_update_alt_outlined),
          title: const Text('检查更新'),
          subtitle: Text(
            version == null || version.isEmpty ? '当前版本：读取中' : '当前版本：$version',
          ),
          trailing: _checking
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          enabled: !_checking,
          onTap: _checking ? null : () => _checkNow(coordinator),
        );
      },
    );
  }

  Future<void> _checkNow(AppUpdatePromptCoordinator coordinator) async {
    setState(() => _checking = true);
    final result = await coordinator.checkNow();
    if (!mounted) {
      return;
    }
    setState(() => _checking = false);

    switch (result) {
      case AppUpdateCheckFailure(:final failure):
        showTransientSnackBar(
          context,
          appUpdateCheckFailureMessage(failure.code),
        );
      case AppUpdateCheckUpToDate():
        showTransientSnackBar(context, '已是最新版本');
      case AppUpdateCheckAvailable(suppression: null):
        // updateVersionInfo already notified the single root UpgradeAlert.
        return;
      case AppUpdateCheckAvailable(:final version, :final suppression?):
        final message = switch (suppression) {
          AppUpdatePromptSuppression.ignored => '发现新版本 v$version，你已忽略此版本',
          AppUpdatePromptSuppression.reminderInterval =>
            '发现新版本 v$version，仍在稍后提醒间隔内',
        };
        showTransientSnackBar(
          context,
          message,
          action: SnackBarAction(
            label: '立即下载',
            onPressed: () => unawaited(_openUpdate(coordinator)),
          ),
        );
    }
  }

  Future<void> _openUpdate(AppUpdatePromptCoordinator coordinator) async {
    final result = await coordinator.openCurrentUpdate();
    if (!mounted || result is AppUpdateLaunchSuccess) {
      return;
    }
    final failure = (result as AppUpdateLaunchFailure).failure;
    showTransientSnackBar(context, appUpdateLaunchFailureMessage(failure.code));
  }
}
