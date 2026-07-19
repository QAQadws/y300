import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppUpdateVerificationResult {
  const AppUpdateVerificationResult();
}

final class AppUpdateVerificationSuccess extends AppUpdateVerificationResult {
  const AppUpdateVerificationSuccess({required this.actualSha256});

  final String actualSha256;
}

final class AppUpdateVerificationFailure extends AppUpdateVerificationResult {
  const AppUpdateVerificationFailure(this.failure);

  final AppUpdateFailure failure;
}
