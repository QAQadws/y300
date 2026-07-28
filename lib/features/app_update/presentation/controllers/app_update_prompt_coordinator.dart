import 'dart:async';

import 'package:upgrader/upgrader.dart';
import 'package:y300/features/app_update/data/gitee/gitee_upgrader_store.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_check_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_download_request_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_download_service.dart';
import 'package:y300/features/app_update/domain/services/app_update_launcher.dart';
import 'package:y300/features/app_update/presentation/app_update_messages.dart';
import 'package:y300/features/app_update/presentation/app_update_upgrader.dart';
import 'package:y300/l10n/app_localizations.dart';

final class AppUpdatePromptCoordinator {
  AppUpdatePromptCoordinator({
    required GiteeLatestReleaseRepository repository,
    required AppUpdateLauncher launcher,
    AppUpdateDownloadService? downloadService,
    AppUpdateFailureReporter? onStoreFailure,
    Upgrader? upgrader,
  }) : _launcher = launcher,
       _downloadService = downloadService,
       _repository = repository,
       upgrader =
           upgrader ?? _createUpgrader(repository, onFailure: onStoreFailure);

  static const Duration alertAgainAfter = Duration(days: 3);

  final AppUpdateLauncher _launcher;
  final AppUpdateDownloadService? _downloadService;
  final GiteeLatestReleaseRepository _repository;
  final Upgrader upgrader;
  final StreamController<void> _promptRequestController =
      StreamController<void>.broadcast();

  Future<AppUpdateCheckResult>? _checkInFlight;
  Future<AppUpdateLaunchResult>? _launchInFlight;
  bool _disposed = false;

  bool get supportsInAppDownload => _downloadService != null;

  /// Requests that the single app-level [UpgradeAlert] evaluates its state.
  ///
  /// The coordinator deliberately exposes an event rather than a widget key
  /// or BuildContext so manual checks can reuse the startup prompt without
  /// coupling the domain-facing service to Flutter presentation details.
  Stream<void> get promptRequestStream => _promptRequestController.stream;

  void requestPrompt() {
    if (_disposed || _promptRequestController.isClosed) {
      return;
    }
    if (upgrader is AppUpdateManualPromptGate) {
      (upgrader as AppUpdateManualPromptGate).prepareManualPrompt();
    }
    _promptRequestController.add(null);
  }

  void cancelPendingPrompt() {
    if (upgrader is AppUpdateManualPromptGate) {
      (upgrader as AppUpdateManualPromptGate).cancelManualPrompt();
    }
  }

  void updateLocalization(AppLocalizations l10n) {
    final messages = upgrader.state.messages;
    if (messages is Y300UpgraderMessages) {
      messages.updateLocalization(l10n);
    }
  }

  String? get installedVersion {
    final value =
        upgrader.currentInstalledVersion?.trim() ??
        upgrader.versionInfo?.installedVersion?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  Stream<String?> get installedVersionStream async* {
    yield installedVersion;
    await for (final _ in upgrader.stateStream) {
      yield installedVersion;
    }
  }

  Future<AppUpdateCheckResult> checkNow() async {
    final inFlight = _checkInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final request = _checkNow();
    _checkInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_checkInFlight, request)) {
        _checkInFlight = null;
      }
    }
  }

  Future<AppUpdateCheckResult> _checkNow() async {
    if (_disposed) {
      return _checkFailure(
        AppUpdateFailureCode.remoteUnavailable,
        'The app update coordinator has been disposed.',
      );
    }

    late GiteeReleaseLookupResult lookup;
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _repository.getLatest(forceRefresh: true),
        upgrader.initialize(),
      ]);
      lookup = results.first! as GiteeReleaseLookupResult;

      // The forced lookup owns the only HTTP request. Upgrader then reads the
      // typed result from the repository cache and notifies the existing host.
      await upgrader.updateVersionInfo();
    } on Object {
      return _checkFailure(
        AppUpdateFailureCode.remoteUnavailable,
        'Checking for updates failed unexpectedly.',
      );
    }

    if (lookup case GiteeReleaseLookupFailure(:final failure)) {
      return AppUpdateCheckFailure(failure);
    }
    final candidate = (lookup as GiteeReleaseLookupSuccess).candidate;
    final currentVersion = installedVersion;
    if (currentVersion == null) {
      return _checkFailure(
        AppUpdateFailureCode.installedVersionUnavailable,
        'The installed app version is unavailable.',
      );
    }
    if (!upgrader.isUpdateAvailable()) {
      return AppUpdateCheckUpToDate(
        installedVersion: currentVersion,
        latestVersion: candidate.version,
      );
    }

    final suppression = upgrader.alreadyIgnoredThisVersion()
        ? AppUpdatePromptSuppression.ignored
        : upgrader.isTooSoon()
        ? AppUpdatePromptSuppression.reminderInterval
        : null;
    return AppUpdateCheckAvailable(
      version: candidate.version,
      suppression: suppression,
    );
  }

  AppUpdateCheckFailure _checkFailure(
    AppUpdateFailureCode code,
    String message,
  ) {
    return AppUpdateCheckFailure(
      AppUpdateFailure(code: code, message: message),
    );
  }

  Future<AppUpdateLaunchResult> openCurrentUpdate() async {
    final inFlight = _launchInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final request = _openCurrentUpdate();
    _launchInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_launchInFlight, request)) {
        _launchInFlight = null;
      }
    }
  }

  /// Resolves the same cached Gitee candidate used by Upgrader and starts the
  /// shared application download service. The service itself owns the
  /// checksum/download/verification/install transaction.
  Future<AppUpdateDownloadRequestResult> startCurrentDownload() async {
    final service = _downloadService;
    if (_disposed || service == null) {
      return const AppUpdateDownloadRequestFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.apkDownloadStartFailed,
          message: 'The in-app update download is unavailable.',
        ),
      );
    }

    late final GiteeReleaseLookupResult lookup;
    try {
      lookup = await _repository.getLatest();
    } on Object {
      return const AppUpdateDownloadRequestFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.remoteUnavailable,
          message: 'The current update could not be resolved.',
        ),
      );
    }
    if (lookup case GiteeReleaseLookupFailure(:final failure)) {
      return AppUpdateDownloadRequestFailure(failure);
    }

    final candidate = (lookup as GiteeReleaseLookupSuccess).candidate;
    late final AppUpdateArtifact artifact;
    try {
      artifact = AppUpdateArtifact.fromCandidate(candidate);
    } on StateError {
      return const AppUpdateDownloadRequestFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.invalidPayload,
          message: 'The current update artifact is invalid.',
        ),
      );
    }

    unawaited(service.start(artifact));
    return AppUpdateDownloadRequestAccepted(artifact);
  }

  /// Reconciles a retained verified artifact with the version currently
  /// installed on the device. Upgrader owns package information; the
  /// download service only decides whether its private artifact can be
  /// discarded.
  Future<void> reconcileInstalledUpdate() async {
    final service = _downloadService;
    if (_disposed || service == null) {
      return;
    }
    try {
      await upgrader.initialize();
      await service.restoreBackground(installedVersion: installedVersion);
      await service.reconcileInstalledVersion(installedVersion);
    } on Object {
      // Installation reconciliation is best effort and must not block the
      // application when package metadata is temporarily unavailable.
    }
  }

  Future<AppUpdateLaunchResult> _openCurrentUpdate() {
    if (_disposed) {
      return Future<AppUpdateLaunchResult>.value(
        const AppUpdateLaunchFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.externalLaunchFailed,
            message: 'The app update coordinator has been disposed.',
          ),
        ),
      );
    }

    final rawUrl = upgrader.currentAppStoreListingURL?.trim();
    final uri = rawUrl == null || rawUrl.isEmpty ? null : Uri.tryParse(rawUrl);
    if (uri == null) {
      return Future<AppUpdateLaunchResult>.value(
        const AppUpdateLaunchFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.invalidAssetUrl,
            message: 'The current update does not have a valid APK URL.',
          ),
        ),
      );
    }
    return _launcher.openApk(uri);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_promptRequestController.close());
    upgrader.dispose();
  }

  static Upgrader _createUpgrader(
    GiteeLatestReleaseRepository repository, {
    AppUpdateFailureReporter? onFailure,
  }) {
    final store = GiteeUpgraderStore(
      repository: repository,
      onFailure: onFailure,
    );
    return Y300Upgrader(
      durationUntilAlertAgain: alertAgainAfter,
      messages: Y300UpgraderMessages(
        lookupAppLocalizations(AppLocalizations.supportedLocales.first),
      ),
      storeController: UpgraderStoreController(
        onAndroid: () => store,
        onFuchsia: null,
        oniOS: null,
        onLinux: null,
        onMacOS: null,
        onWeb: null,
        onWindows: null,
      ),
    );
  }
}
