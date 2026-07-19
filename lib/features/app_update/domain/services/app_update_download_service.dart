import 'dart:async';

import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';
import 'package:y300/features/app_update/domain/models/app_update_background_task.dart';
import 'package:y300/features/app_update/domain/models/app_update_background_notification_tap.dart';
import 'package:y300/features/app_update/domain/models/app_update_binary_event.dart';
import 'package:y300/features/app_update/domain/models/app_update_download_state.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_verification_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/app_update_checksum_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_artifact_verifier.dart';
import 'package:y300/features/app_update/domain/services/app_update_background_binary_downloader.dart';
import 'package:y300/features/app_update/domain/services/app_update_binary_downloader.dart';
import 'package:y300/features/app_update/domain/services/app_update_file_store.dart';
import 'package:y300/features/app_update/domain/services/app_update_installer.dart';

/// Coordinates one foreground update transaction.
///
/// This service deliberately owns no Flutter state. Widgets consume the
/// stream, while the service keeps the ordering that protects the installer:
/// checksum -> staging download -> verification -> atomic promotion.
final class AppUpdateDownloadService {
  AppUpdateDownloadService({
    required AppUpdateChecksumRepository checksumRepository,
    required AppUpdateBinaryDownloader binaryDownloader,
    required AppUpdateArtifactVerifier verifier,
    required AppUpdateFileStore fileStore,
    required AppUpdateInstaller installer,
  }) : _checksumRepository = checksumRepository,
       _binaryDownloader = binaryDownloader,
       _verifier = verifier,
       _fileStore = fileStore,
       _installer = installer {
    if (binaryDownloader is AppUpdateBackgroundBinaryDownloader) {
      _notificationTapSubscription = binaryDownloader.notificationTapStream
          .listen((tap) => unawaited(_restoreForNotificationTap(tap)));
    }
  }

  final AppUpdateChecksumRepository _checksumRepository;
  final AppUpdateBinaryDownloader _binaryDownloader;
  final AppUpdateArtifactVerifier _verifier;
  final AppUpdateFileStore _fileStore;
  final AppUpdateInstaller _installer;
  final StreamController<AppUpdateDownloadState> _stateController =
      StreamController<AppUpdateDownloadState>.broadcast();

  AppUpdateDownloadState _state = const AppUpdateIdle();
  Future<AppUpdateDownloadState>? _downloadInFlight;
  Future<AppUpdateDownloadState>? _installInFlight;
  Future<void>? _restoreInFlight;
  StreamSubscription<AppUpdateBackgroundNotificationTap>?
  _notificationTapSubscription;
  AppUpdateArtifact? _lastArtifact;
  AppUpdateReadyToInstall? _lastReadyToInstall;
  bool _disposed = false;

  AppUpdateDownloadState get state => _state;

  Stream<AppUpdateDownloadState> get stateStream => _stateController.stream;

  /// Reconnects the in-memory state machine to a task owned by the background
  /// downloader database. No APK bytes or duplicate task records are created.
  Future<void> restoreBackground({
    String? installedVersion,
    AppUpdateArtifactIdentity? identity,
  }) {
    final inFlight = _restoreInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _restoreBackground(
      installedVersion: installedVersion,
      identity: identity,
    );
    _restoreInFlight = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_restoreInFlight, operation)) {
          _restoreInFlight = null;
        }
      }),
    );
    return operation;
  }

  Future<void> _restoreBackground({
    String? installedVersion,
    AppUpdateArtifactIdentity? identity,
  }) async {
    final background = _binaryDownloader;
    if (background is! AppUpdateBackgroundBinaryDownloader) {
      return;
    }
    try {
      await background.initialize();
      final snapshots = await background.recover();
      await _fileStore.cleanupStaleArtifacts();
      if (snapshots.isEmpty || _downloadInFlight != null) {
        return;
      }
      snapshots.sort(_recoveryPriority);
      final snapshot = identity == null
          ? snapshots.first
          : snapshots
                .where(
                  (candidate) =>
                      candidate.identity.stableKey == identity.stableKey,
                )
                .firstOrNull;
      if (snapshot == null) {
        return;
      }
      final alreadyPresented =
          _lastArtifact?.identityKey == snapshot.artifact.identityKey &&
          (_state is AppUpdateReadyToInstall ||
              _state is AppUpdateInstalling ||
              _state is AppUpdateIdle);
      _lastArtifact = snapshot.artifact;
      if (_isInstalledVersionAtLeast(installedVersion, snapshot.artifact)) {
        await _clearArtifact();
        return;
      }
      if (alreadyPresented) {
        return;
      }
      switch (snapshot.status) {
        case AppUpdateBackgroundTaskStatus.failed:
        case AppUpdateBackgroundTaskStatus.notFound:
          _emit(
            AppUpdateFailed(
              artifact: snapshot.artifact,
              failure:
                  snapshot.failure ??
                  const AppUpdateFailure(
                    code: AppUpdateFailureCode.apkDownloadFailed,
                    message: 'The background update task is no longer active.',
                  ),
            ),
          );
        case AppUpdateBackgroundTaskStatus.canceled:
          await _invalidateDownloadedArtifact(snapshot.artifact);
          _lastArtifact = null;
          _emit(const AppUpdateIdle());
        case AppUpdateBackgroundTaskStatus.enqueued:
        case AppUpdateBackgroundTaskStatus.running:
        case AppUpdateBackgroundTaskStatus.waitingToRetry:
        case AppUpdateBackgroundTaskStatus.complete:
          await start(snapshot.artifact);
        case AppUpdateBackgroundTaskStatus.paused:
          await _invalidateDownloadedArtifact(snapshot.artifact);
          await start(snapshot.artifact);
      }
    } on Object {
      // A missing plugin, denied notification permission or stale task must
      // never prevent the rest of the app from starting.
    }
  }

  /// Starts or joins the foreground download for [artifact].
  ///
  /// Calling this method repeatedly for the same artifact is single-flight.
  /// A different artifact is rejected while the current transaction is
  /// active, so an old prompt cannot replace a newer in-progress update.
  Future<AppUpdateDownloadState> start(AppUpdateArtifact artifact) {
    if (_disposed) {
      return Future<AppUpdateDownloadState>.value(
        _failed(
          artifact,
          const AppUpdateFailure(
            code: AppUpdateFailureCode.apkDownloadStartFailed,
            message: 'The update download service has been disposed.',
          ),
          emit: false,
        ),
      );
    }

    final inFlight = _downloadInFlight;
    if (inFlight != null) {
      final activeArtifact = _lastArtifact;
      if (activeArtifact?.identityKey == artifact.identityKey) {
        return inFlight;
      }
      return Future<AppUpdateDownloadState>.value(
        _failed(
          artifact,
          const AppUpdateFailure(
            code: AppUpdateFailureCode.apkDownloadStartFailed,
            message: 'Another update download is already in progress.',
          ),
          emit: false,
        ),
      );
    }

    _lastArtifact = artifact;
    _lastReadyToInstall = null;
    final operation = _runDownload(artifact);
    _downloadInFlight = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_downloadInFlight, operation)) {
          _downloadInFlight = null;
        }
      }),
    );
    return operation;
  }

  Future<AppUpdateDownloadState> retry() {
    final artifact = _lastArtifact;
    if (artifact == null) {
      return Future<AppUpdateDownloadState>.value(_state);
    }
    if (_state case AppUpdateFailed(:final recoveryAction)) {
      if (recoveryAction == AppUpdateRecoveryAction.retryInstall) {
        return installReady();
      }
      if (recoveryAction == AppUpdateRecoveryAction.retryDownload) {
        return _retryDownload(artifact);
      }
    }
    final inFlight = _downloadInFlight;
    if (inFlight != null &&
        _state is AppUpdateFailed &&
        artifact.identityKey == _lastArtifact?.identityKey) {
      return inFlight.then((_) => start(artifact));
    }
    return start(artifact);
  }

  Future<AppUpdateDownloadState> _retryDownload(
    AppUpdateArtifact artifact,
  ) async {
    final inFlight = _downloadInFlight;
    if (inFlight != null) {
      await inFlight;
    }
    await _invalidateDownloadedArtifact(artifact);
    return start(artifact);
  }

  Future<void> cancel() async {
    if (_downloadInFlight == null) {
      return;
    }
    final inFlight = _downloadInFlight!;
    await _binaryDownloader.cancel();
    await inFlight;
    if (_state case AppUpdateFailed(
      failure: AppUpdateFailure(
        code: AppUpdateFailureCode.apkDownloadCancelled,
      ),
    )) {
      await _clearArtifact();
    }
  }

  /// Removes an update artifact after Android has installed an equal or
  /// newer version. The installed version is read by the presentation
  /// boundary through Upgrader, so this service remains platform-agnostic.
  Future<void> reconcileInstalledVersion(String? installedVersion) async {
    final artifact = _lastArtifact;
    if (artifact == null || _downloadInFlight != null) {
      return;
    }
    final rawVersion = installedVersion?.trim();
    if (rawVersion == null || rawVersion.isEmpty) {
      return;
    }
    final currentVersion = _parseVersion(rawVersion);
    if (currentVersion == null) {
      return;
    }
    if (currentVersion < artifact.version) {
      if (_state is AppUpdateInstalling) {
        _emit(const AppUpdateIdle());
      }
      return;
    }
    await _clearArtifact();
  }

  /// Opens the Android installer for the last verified APK.
  Future<AppUpdateDownloadState> installReady() {
    final current = _state;
    final ready = switch (current) {
      AppUpdateReadyToInstall() => current,
      AppUpdateFailed(recoveryAction: AppUpdateRecoveryAction.retryInstall) =>
        _lastReadyToInstall,
      _ => null,
    };
    if (ready == null) {
      return Future<AppUpdateDownloadState>.value(current);
    }
    final inFlight = _installInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final operation = _install(ready);
    _installInFlight = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_installInFlight, operation)) {
          _installInFlight = null;
        }
      }),
    );
    return operation;
  }

  /// Hides the panel and removes this service's update artifact.
  Future<void> reset() async {
    if (_isBusyState(_state)) {
      return;
    }
    final downloadInFlight = _downloadInFlight;
    if (downloadInFlight != null) {
      await downloadInFlight;
    }
    final installInFlight = _installInFlight;
    if (installInFlight != null) {
      await installInFlight;
    }
    await _clearArtifact();
  }

  /// Hides the panel while retaining a verified APK that the system installer
  /// may still be reading. A later update attempt will replace it safely.
  Future<void> dismiss() async {
    if (_state is AppUpdateInstalling) {
      _emit(const AppUpdateIdle());
      return;
    }
    if (_isBusyState(_state)) {
      return;
    }
    _emit(const AppUpdateIdle());
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _notificationTapSubscription?.cancel();
    if (_binaryDownloader is! AppUpdateBackgroundBinaryDownloader) {
      await cancel();
    }
    await _stateController.close();
  }

  Future<AppUpdateDownloadState> _runDownload(
    AppUpdateArtifact artifact,
  ) async {
    _emit(AppUpdatePreparing(artifact));

    // A completed background task may already have been atomically promoted
    // to verified storage. Re-verify that file directly instead of asking a
    // plugin task whose staging path no longer exists to download it again.
    try {
      final verifiedPath = await _fileStore.verifiedPath(artifact.identity);
      if (await _fileStore.exists(verifiedPath)) {
        return _restoreVerifiedArtifact(artifact, verifiedPath);
      }
    } on Object {
      // Fall back to the normal staging download path below.
    }

    AppUpdateChecksumLookupResult checksumResult;
    try {
      checksumResult = await _checksumRepository.fetchChecksum(artifact);
    } on Object {
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.checksumRequestFailed,
          message: 'The update checksum request failed.',
        ),
      );
    }
    if (checksumResult case AppUpdateChecksumLookupFailure(:final failure)) {
      return _failed(artifact, failure);
    }
    final checksum =
        (checksumResult as AppUpdateChecksumLookupSuccess).checksum;

    late final String stagingPath;
    try {
      final background = _binaryDownloader;
      final hasRecoverableTask =
          background is AppUpdateBackgroundBinaryDownloader
          ? await _hasRecoverableTask(background, artifact)
          : false;
      if (!hasRecoverableTask) {
        await _fileStore.deleteArtifact(artifact.identity);
      }
      stagingPath = await _fileStore.stagingPath(artifact.identity);
    } on Object {
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.insufficientStorage,
          message: 'There is not enough private storage for the update.',
        ),
      );
    }

    var completed = false;
    try {
      await for (final event in _binaryDownloader.download(
        artifact,
        stagingPath: stagingPath,
      )) {
        if (event.identity.stableKey != artifact.identity.stableKey) {
          return _failed(
            artifact,
            const AppUpdateFailure(
              code: AppUpdateFailureCode.apkDownloadFailed,
              message: 'The update download returned an unexpected artifact.',
            ),
          );
        }
        switch (event.type) {
          case AppUpdateBinaryEventType.started:
          case AppUpdateBinaryEventType.progress:
            _emit(
              AppUpdateDownloading(
                artifact: artifact,
                progress: event.progress,
                receivedBytes: event.receivedBytes,
                totalBytes: event.totalBytes,
              ),
            );
          case AppUpdateBinaryEventType.completed:
            completed = true;
          case AppUpdateBinaryEventType.cancelled:
            await _invalidateDownloadedArtifact(artifact);
            return _failed(
              artifact,
              event.failure ??
                  const AppUpdateFailure(
                    code: AppUpdateFailureCode.apkDownloadCancelled,
                    message: 'The update download was cancelled.',
                  ),
            );
          case AppUpdateBinaryEventType.failed:
            return _failed(
              artifact,
              event.failure ??
                  const AppUpdateFailure(
                    code: AppUpdateFailureCode.apkDownloadFailed,
                    message: 'The update download failed.',
                  ),
            );
        }
      }
    } on Object {
      await _invalidateDownloadedArtifact(artifact);
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.apkDownloadFailed,
          message: 'The update download failed unexpectedly.',
        ),
      );
    }

    if (!completed) {
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.apkDownloadFailed,
          message: 'The update download ended before completion.',
        ),
      );
    }

    _emit(AppUpdateVerifying(artifact));
    late final AppUpdateVerificationResult verification;
    try {
      verification = await _verifier.verify(
        artifact: artifact,
        checksum: checksum,
        apkPath: stagingPath,
      );
    } on Object {
      await _invalidateDownloadedArtifact(artifact);
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.apkReadFailed,
          message: 'The downloaded APK could not be verified.',
        ),
      );
    }
    if (verification case AppUpdateVerificationFailure(:final failure)) {
      await _invalidateDownloadedArtifact(artifact);
      return _failed(artifact, failure);
    }

    late final String verifiedPath;
    try {
      verifiedPath = await _fileStore.verifiedPath(artifact.identity);
      await _fileStore.promote(
        stagingPath: stagingPath,
        verifiedPath: verifiedPath,
      );
    } on Object {
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.apkPromotionFailed,
          message: 'The verified update could not be staged for installation.',
        ),
      );
    }

    final ready = AppUpdateReadyToInstall(
      artifact: artifact,
      apkPath: verifiedPath,
    );
    _lastReadyToInstall = ready;
    return _install(ready);
  }

  Future<AppUpdateDownloadState> _install(AppUpdateReadyToInstall ready) async {
    _emit(
      AppUpdateInstalling(artifact: ready.artifact, apkPath: ready.apkPath),
    );
    late final AppUpdateInstallResult result;
    try {
      result = await _installer.install(
        apkPath: ready.apkPath,
        artifact: ready.artifact,
      );
    } on Object {
      _lastReadyToInstall = ready;
      return _failed(
        ready.artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.installerLaunchFailed,
          message: 'The Android installer could not be opened.',
        ),
        recoveryAction: AppUpdateRecoveryAction.retryInstall,
      );
    }
    switch (result) {
      case AppUpdateInstallLaunched():
        final launched = AppUpdateInstalling(
          artifact: ready.artifact,
          apkPath: ready.apkPath,
        );
        _emit(launched);
        return launched;
      case AppUpdateInstallPermissionRequired(:final permanentlyDenied):
        return _failed(
          ready.artifact,
          AppUpdateFailure(
            code: AppUpdateFailureCode.installPermissionRequired,
            message: permanentlyDenied
                ? 'Allow Y300 to install unknown apps in Android settings.'
                : 'Allow Y300 to install this update, then retry.',
          ),
          recoveryAction: AppUpdateRecoveryAction.retryInstall,
        );
      case AppUpdateInstallUnavailable():
        return _failed(
          ready.artifact,
          const AppUpdateFailure(
            code: AppUpdateFailureCode.installerUnavailable,
            message: 'No Android installer is available for this APK.',
          ),
          recoveryAction: AppUpdateRecoveryAction.retryInstall,
        );
      case AppUpdateInstallFailure(:final failure):
        return _failed(
          ready.artifact,
          failure,
          recoveryAction: AppUpdateRecoveryAction.retryInstall,
        );
    }
  }

  AppUpdateDownloadState _failed(
    AppUpdateArtifact artifact,
    AppUpdateFailure failure, {
    bool emit = true,
    AppUpdateRecoveryAction? recoveryAction,
  }) {
    final failed = AppUpdateFailed(
      artifact: artifact,
      failure: failure,
      recoveryAction: recoveryAction ?? AppUpdateRecoveryAction.retryDownload,
    );
    if (emit) {
      _emit(failed);
    }
    return failed;
  }

  void _emit(AppUpdateDownloadState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  Future<void> _clearArtifact() async {
    final artifact = _lastArtifact;
    if (artifact == null) {
      _emit(const AppUpdateIdle());
      return;
    }
    final background = _binaryDownloader;
    if (background is AppUpdateBackgroundBinaryDownloader) {
      try {
        await background.discard(artifact.identity);
      } on Object {
        // File cleanup remains useful even when the plugin record is stale.
      }
    }
    await _fileStore.deleteArtifact(artifact.identity);
    _lastArtifact = null;
    _lastReadyToInstall = null;
    _emit(const AppUpdateIdle());
  }

  bool _isBusyState(AppUpdateDownloadState state) {
    return state is AppUpdatePreparing ||
        state is AppUpdateDownloading ||
        state is AppUpdateVerifying ||
        state is AppUpdateInstalling;
  }

  bool _isInstalledVersionAtLeast(
    String? installedVersion,
    AppUpdateArtifact artifact,
  ) {
    final rawVersion = installedVersion?.trim();
    if (rawVersion == null || rawVersion.isEmpty) {
      return false;
    }
    final currentVersion = _parseVersion(rawVersion);
    return currentVersion != null && currentVersion >= artifact.version;
  }

  Version? _parseVersion(String rawVersion) {
    try {
      return Version.parse(rawVersion);
    } on Object {
      return null;
    }
  }

  Future<AppUpdateDownloadState> _restoreVerifiedArtifact(
    AppUpdateArtifact artifact,
    String verifiedPath,
  ) async {
    AppUpdateChecksumLookupResult checksumResult;
    try {
      checksumResult = await _checksumRepository.fetchChecksum(artifact);
    } on Object {
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.checksumRequestFailed,
          message: 'The update checksum request failed.',
        ),
      );
    }
    if (checksumResult case AppUpdateChecksumLookupFailure(:final failure)) {
      return _failed(artifact, failure);
    }
    final checksum =
        (checksumResult as AppUpdateChecksumLookupSuccess).checksum;
    _emit(AppUpdateVerifying(artifact));
    late final AppUpdateVerificationResult verification;
    try {
      verification = await _verifier.verify(
        artifact: artifact,
        checksum: checksum,
        apkPath: verifiedPath,
      );
    } on Object {
      await _invalidateVerifiedArtifact(artifact);
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.apkReadFailed,
          message: 'The downloaded APK could not be verified.',
        ),
      );
    }
    if (verification case AppUpdateVerificationFailure(:final failure)) {
      await _invalidateDownloadedArtifact(artifact);
      return _failed(artifact, failure);
    }
    final ready = AppUpdateReadyToInstall(
      artifact: artifact,
      apkPath: verifiedPath,
    );
    _lastReadyToInstall = ready;
    return _install(ready);
  }

  Future<void> _invalidateDownloadedArtifact(AppUpdateArtifact artifact) async {
    if (_lastReadyToInstall?.artifact.identityKey == artifact.identityKey) {
      _lastReadyToInstall = null;
    }
    await _invalidateVerifiedArtifact(artifact);
  }

  Future<void> _restoreForNotificationTap(
    AppUpdateBackgroundNotificationTap tap,
  ) async {
    await restoreBackground(identity: tap.identity);
  }

  Future<void> _invalidateVerifiedArtifact(AppUpdateArtifact artifact) async {
    await _discardBackgroundTask(artifact);
    try {
      await _fileStore.deleteArtifact(artifact.identity);
    } on Object {
      // A later retry can still replace the file if cleanup is temporarily
      // blocked by the platform.
    }
  }

  Future<void> _discardBackgroundTask(AppUpdateArtifact artifact) async {
    final background = _binaryDownloader;
    if (background is! AppUpdateBackgroundBinaryDownloader) {
      return;
    }
    try {
      await background.discard(artifact.identity);
    } on Object {
      // A stale plugin record must not prevent a retryable UI state.
    }
  }

  Future<bool> _hasRecoverableTask(
    AppUpdateBackgroundBinaryDownloader background,
    AppUpdateArtifact artifact,
  ) async {
    try {
      return await background.hasRecoverableTask(artifact.identity);
    } on Object {
      return false;
    }
  }

  int _recoveryPriority(
    AppUpdateBackgroundTaskSnapshot first,
    AppUpdateBackgroundTaskSnapshot second,
  ) {
    int rank(AppUpdateBackgroundTaskStatus status) {
      return switch (status) {
        AppUpdateBackgroundTaskStatus.running => 0,
        AppUpdateBackgroundTaskStatus.paused => 1,
        AppUpdateBackgroundTaskStatus.enqueued => 2,
        AppUpdateBackgroundTaskStatus.waitingToRetry => 3,
        AppUpdateBackgroundTaskStatus.complete => 4,
        AppUpdateBackgroundTaskStatus.failed => 5,
        AppUpdateBackgroundTaskStatus.canceled => 6,
        AppUpdateBackgroundTaskStatus.notFound => 7,
      };
    }

    return rank(first.status).compareTo(rank(second.status));
  }
}
