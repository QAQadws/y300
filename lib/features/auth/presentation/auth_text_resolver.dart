import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/presentation/login_state.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

abstract final class AuthTextResolver {
  static String loginFailure(AppLocalizations l10n, AuthLoginFailure failure) {
    final detail = failure.detail;
    if (failure.code == AuthLoginFailureCode.requestFailed &&
        detail is ApiError &&
        detail.type == ApiErrorType.business) {
      return l10n.authLoginRejected;
    }
    return switch (failure.code) {
      AuthLoginFailureCode.credentialsRequired => l10n.authCredentialsRequired,
      AuthLoginFailureCode.timeout => l10n.authLoginTimeout,
      AuthLoginFailureCode.requestFailed => l10n.authLoginFailed(
        LocalizedErrorSummary.resolve(l10n, detail),
      ),
    };
  }

  static String webViewFailure(AppLocalizations l10n, Object? detail) {
    return l10n.authWebViewVerificationFailed(
      LocalizedErrorSummary.resolve(l10n, detail),
    );
  }
}
