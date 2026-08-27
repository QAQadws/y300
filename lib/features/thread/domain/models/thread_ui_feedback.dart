import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Stable UI-facing semantics emitted by the thread controller.
///
/// These values deliberately do not contain localized text. Presentation
/// resolves them through [AppLocalizations] at the last possible boundary.
enum ThreadUiErrorCode {
  loadFailed,
  refreshFailed,
  pageLoadFailed,
  favoriteFailed,
  voteFailed,
  rateFailed,
  commentFailed,
  replyFailed,
  loginRequired,
  permissionDenied,
  validation,
  unsupported,
  unknown,
}

enum ThreadActionKind { favorite, vote, rate, comment, reply, ratings }

enum ThreadActionNoticeCode {
  success,
  partialSuccess,
  failure,
  loginRequired,
  permissionDenied,
  validation,
  unsupported,
  unknown,
}

final class ThreadActionFailure {
  const ThreadActionFailure({
    required this.code,
    this.action,
    this.detail,
    @Deprecated('Use code and detail for presentation.') this.message,
  });

  final ThreadUiErrorCode code;
  final ThreadActionKind? action;
  final String? detail;

  @Deprecated('Use code and detail for presentation.')
  final String? message;
}

final class ThreadActionNotice {
  const ThreadActionNotice({
    required this.code,
    this.action,
    this.detail,
    this.maxChoices,
    this.commandFailure,
    @Deprecated('Use code and detail for presentation.') this.message,
  });

  final ThreadActionNoticeCode code;
  final ThreadActionKind? action;
  final String? detail;
  final int? maxChoices;
  final DataCommandFailure? commandFailure;

  @Deprecated('Use code and detail for presentation.')
  final String? message;
}
