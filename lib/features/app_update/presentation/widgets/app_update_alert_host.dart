import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:upgrader/upgrader.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/presentation/app_update_feedback_messages.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

class AppUpdateAlertHost extends ConsumerStatefulWidget {
  const AppUpdateAlertHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateAlertHost> createState() => _AppUpdateAlertHostState();
}

class _AppUpdateAlertHostState extends ConsumerState<AppUpdateAlertHost> {
  @override
  Widget build(BuildContext context) {
    final coordinator = ref.watch(appUpdatePromptCoordinatorProvider);
    return UpgradeAlert(
      upgrader: coordinator.upgrader,
      barrierDismissible: false,
      showIgnore: true,
      showLater: true,
      showReleaseNotes: true,
      onUpdate: () {
        unawaited(_openUpdate(coordinator));
        return false;
      },
      child: widget.child,
    );
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
