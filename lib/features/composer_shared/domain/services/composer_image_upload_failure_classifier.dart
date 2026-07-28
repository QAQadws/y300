import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';

class ComposerImageUploadFailureClassifier {
  const ComposerImageUploadFailureClassifier();

  ComposerImageUploadFailure classify(ApiError error) {
    final stableCode = error.code?.trim();
    final parsed = ComposerImageUploadFailureCode.values
        .where((value) => value.name == stableCode)
        .firstOrNull;
    final code =
        parsed ??
        switch (error.type) {
          ApiErrorType.unauthorized =>
            ComposerImageUploadFailureCode.permissionExpired,
          ApiErrorType.timeout => ComposerImageUploadFailureCode.timeout,
          ApiErrorType.network => ComposerImageUploadFailureCode.network,
          ApiErrorType.server => ComposerImageUploadFailureCode.server,
          _ => ComposerImageUploadFailureCode.unknown,
        };
    final detail = error.message.trim();
    return ComposerImageUploadFailure(
      code: code,
      detail: detail.isEmpty ? null : detail,
    );
  }
}
