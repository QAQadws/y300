import 'dart:async';

import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_binary_event.dart';
import 'package:y300/features/app_update/domain/models/app_update_download_state.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_verification_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/app_update_checksum_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_artifact_verifier.dart';
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
       _installer = installer;

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
  AppUpdateArtifact? _lastArtifact;
  bool _disposed = false;

  AppUpdateDownloadState get state => _state;

  Stream<AppUpdateDownloadState> get stateStream => _stateController.stream;

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
    final inFlight = _downloadInFlight;
    if (inFlight != null &&
        _state is AppUpdateFailed &&
        artifact.identityKey == _lastArtifact?.identityKey) {
      return inFlight.then((_) => start(artifact));
    }
    return start(artifact);
  }

  Future<void> cancel() async {
    if (_downloadInFlight == null) {
      return;
    }
    await _binaryDownloader.cancel();
  }

  /// Opens the Android installer for the last verified APK.
  Future<AppUpdateDownloadState> installReady() {
    final current = _state;
    if (current is! AppUpdateReadyToInstall) {
      return Future<AppUpdateDownloadState>.value(current);
    }
    final inFlight = _installInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final operation = _install(current);
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
    final artifact = _lastArtifact;
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
    if (artifact != null) {
      await _fileStore.deleteArtifact(artifact.identity);
    }
    _lastArtifact = null;
    _emit(const AppUpdateIdle());
  }

  /// Hides the panel while retaining a verified APK that the system installer
  /// may still be reading. A later update attempt will replace it safely.
  Future<void> dismiss() async {
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
    await cancel();
    await _stateController.close();
  }

  Future<AppUpdateDownloadState> _runDownload(
    AppUpdateArtifact artifact,
  ) async {
    _emit(AppUpdatePreparing(artifact));

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
      await _fileStore.deleteArtifact(artifact.identity);
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
      return _failed(
        artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.apkReadFailed,
          message: 'The downloaded APK could not be verified.',
        ),
      );
    }
    if (verification case AppUpdateVerificationFailure(:final failure)) {
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
    _emit(ready);
    return ready;
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
      return _failed(
        ready.artifact,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.installerLaunchFailed,
          message: 'The Android installer could not be opened.',
        ),
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
        );
      case AppUpdateInstallUnavailable():
        return _failed(
          ready.artifact,
          const AppUpdateFailure(
            code: AppUpdateFailureCode.installerUnavailable,
            message: 'No Android installer is available for this APK.',
          ),
        );
      case AppUpdateInstallFailure(:final failure):
        return _failed(ready.artifact, failure);
    }
  }

  AppUpdateDownloadState _failed(
    AppUpdateArtifact artifact,
    AppUpdateFailure failure, {
    bool emit = true,
  }) {
    final failed = AppUpdateFailed(artifact: artifact, failure: failure);
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

  bool _isBusyState(AppUpdateDownloadState state) {
    return state is AppUpdatePreparing ||
        state is AppUpdateDownloading ||
        state is AppUpdateVerifying ||
        state is AppUpdateInstalling;
  }
}
