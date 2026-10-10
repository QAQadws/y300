import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:upgrader/upgrader.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_update_download_request_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/presentation/app_update_feedback_messages.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

class AppUpdateAlertHost extends ConsumerStatefulWidget {
  const AppUpdateAlertHost({
    super.key,
    required this.child,
    this.onBlockedChanged,
  });

  final Widget child;

  /// Blocks optional main-shell work until startup evaluation has settled.
  final ValueChanged<bool>? onBlockedChanged;

  @override
  ConsumerState<AppUpdateAlertHost> createState() => _AppUpdateAlertHostState();
}

class _AppUpdateAlertHostState extends ConsumerState<AppUpdateAlertHost>
    with WidgetsBindingObserver {
  final GlobalKey<UpgradeAlertState> _alertKey = GlobalKey<UpgradeAlertState>();
  StreamSubscription<void>? _promptRequestSubscription;
  bool _startupReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _promptRequestSubscription = ref
        .read(appUpdatePromptCoordinatorProvider)
        .promptRequestStream
        .listen((_) => _schedulePromptEvaluation());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_reconcileInstalledUpdate());
        if (widget.onBlockedChanged != null) {
          unawaited(_waitForStartupEvaluation());
        }
      }
    });
  }

  @override
  void dispose() {
    unawaited(_promptRequestSubscription?.cancel());
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
    coordinator.updateLocalization(AppLocalizations.of(context));
    return _AvailabilityUpgradeAlert(
      onAvailabilityChanged: _publishAvailability,
      key: _alertKey,
      upgrader: coordinator.upgrader,
      barrierDismissible: false,
      showIgnore: true,
      showLater: true,
      showReleaseNotes: true,
      onUpdate: () {
        unawaited(_startOrOpenUpdate(coordinator));
        return false;
      },
      // Download progress belongs to the Android notification. Do not mount
      // a route-wide barrier or panel that blocks the rest of the app.
      child: widget.child,
    );
  }

  Future<void> _waitForStartupEvaluation() async {
    try {
      // Upgrader shares this initialization future with UpgradeAlert itself.
      await ref.read(appUpdatePromptCoordinatorProvider).upgrader.initialize();
    } on Object {
      // An update check failure must not indefinitely block unrelated browsing.
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startupReady = true;
      _publishAvailability();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _publishAvailability() {
    if (mounted) {
      widget.onBlockedChanged?.call(
        !_startupReady || _alertKey.currentState?.displayed == true,
      );
    }
  }

  void _schedulePromptEvaluation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final alertState = _alertKey.currentState;
      if (alertState == null) {
        return;
      }
      if (alertState.displayed) {
        ref.read(appUpdatePromptCoordinatorProvider).cancelPendingPrompt();
        return;
      }
      alertState.checkVersion(context: context);
    });
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
          AppLocalizations.of(context),
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
    showTransientSnackBar(
      context,
      appUpdateLaunchFailureMessage(AppLocalizations.of(context), failure.code),
    );
  }
}

/// UpgradeAlert schedules its dialog after evaluation. Retire clipboard work
/// before that delayed Navigator push becomes observable.
class _AvailabilityUpgradeAlert extends UpgradeAlert {
  _AvailabilityUpgradeAlert({
    required this.onAvailabilityChanged,
    required super.key,
    required super.upgrader,
    required super.barrierDismissible,
    required super.showIgnore,
    required super.showLater,
    required super.showReleaseNotes,
    required super.onUpdate,
    required super.child,
  });

  final VoidCallback onAvailabilityChanged;

  @override
  UpgradeAlertState createState() => _AvailabilityUpgradeAlertState();
}

class _AvailabilityUpgradeAlertState extends UpgradeAlertState {
  void _publish() =>
      (widget as _AvailabilityUpgradeAlert).onAvailabilityChanged();

  @override
  void checkVersion({required BuildContext context}) {
    super.checkVersion(context: context);
    _publish();
  }

  @override
  void popNavigator(BuildContext context) {
    super.popNavigator(context);
    _publish();
  }
}
