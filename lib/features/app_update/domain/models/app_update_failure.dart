enum AppUpdateFailureCode {
  invalidPayload,
  missingRequiredField,
  invalidFieldType,
  invalidTag,
  prerelease,
  assetMissing,
  assetAmbiguous,
  invalidAssetUrl,
  checksumAssetMissing,
  checksumAssetAmbiguous,
  invalidChecksumAssetUrl,
  checksumRequestFailed,
  checksumMalformed,
  checksumFileNameMismatch,
  checksumContentTooLarge,
  apkFileMissing,
  apkSizeExceeded,
  apkReadFailed,
  apkHashMismatch,
  networkUnavailable,
  requestTimeout,
  rateLimited,
  releaseNotFound,
  remoteUnavailable,
  installedVersionUnavailable,
  externalLaunchUnavailable,
  externalLaunchFailed,
}

final class AppUpdateFailure {
  const AppUpdateFailure({
    required this.code,
    required this.message,
    this.field,
  });

  final AppUpdateFailureCode code;
  final String message;
  final String? field;
}
