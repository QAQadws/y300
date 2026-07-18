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
  checksumMalformed,
  checksumFileNameMismatch,
  checksumMismatch,
  invalidLocalVersion,
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
