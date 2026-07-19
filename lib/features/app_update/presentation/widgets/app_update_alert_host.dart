import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:upgrader/upgrader.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_update_download_request_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/presentation/app_update_feedback_messages.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';
import 'package:y300/features/app_update/presentation/widgets/app_update_download_host.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

class AppUpdateAlertHost extends ConsumerStatefulWidget {
  const AppUpdateAlertHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateAlertHost> createState() => _AppUpdateAlertHostState();
}

class _AppUpdateAlertHostState extends ConsumerState<AppUpdateAlertHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_reconcileInstalledUpdate());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcileInstalledUpdate());
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = ref.watch(appUpdatePromptCoordinatorProvider);
    final child = coordinator.supportsInAppDownload
        ? AppUpdateDownloadHost(child: widget.child)
        : widget.child;
    return UpgradeAlert(
      upgrader: coordinator.upgrader,
      barrierDismissible: false,
      showIgnore: true,
      showLater: true,
      showReleaseNotes: true,
      onUpdate: () {
        unawaited(_startOrOpenUpdate(coordinator));
        return false;
      },
      child: child,
    );
  }

  Future<void> _reconcileInstalledUpdate() {
    return ref
        .read(appUpdatePromptCoordinatorProvider)
        .reconcileInstalledUpdate();
  }

  Future<void> _startOrOpenUpdate(
    AppUpdatePromptCoordinator coordinator,
  ) async {
    if (coordinator.supportsInAppDownload) {
      final result = await coordinator.startCurrentDownload();
      if (!mounted || result is AppUpdateDownloadRequestAccepted) {
        return;
      }
      showTransientSnackBar(
        context,
        appUpdateDownloadRequestFailureMessage(
          (result as AppUpdateDownloadRequestFailure).failure.code,
        ),
      );
      return;
    }
    await _openUpdate(coordinator);
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
