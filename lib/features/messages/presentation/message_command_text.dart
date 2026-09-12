import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

/// Only stable failure codes reach UI; server response prose is never shown.
String? privateMessageCommandText(
  AppLocalizations l10n,
  DataCommandResult<ForumPrivateMessageReceipt>? result,
) {
  if (result is DataCommandOutcomeUnknown) return l10n.messageUnknownOutcome;
  final failure = result?.failureOrNull;
  if (failure == null) return null;
  return switch (failure.code) {
    'message_can_not_send_onlyfriend' => l10n.messageOnlyFriends,
    'message_bad_touid' ||
    'message_bad_touser' => l10n.messageRecipientUnavailable,
    'message_can_not_send_to_self' ||
    'message_can_not_send_8' => l10n.messageCannotSendToSelf,
    'no_privilege_sendpm' ||
    'is_blacklist' ||
    'message_can_not_send_4' ||
    'message_can_not_send_6' ||
    'message_can_not_send_9' ||
    'message_can_not_send_12' => l10n.messageSendDenied,
    'message_can_not_send_2' => l10n.messageSendTooFast,
    'message_can_not_send_1' ||
    'message_can_not_send_5' ||
    'message_can_not_send_16' => l10n.messageDailyLimit,
    'message_can_not_send_11' ||
    'message_can_not_send_13' ||
    'message_can_not_send_14' => l10n.messageConversationUnavailable,
    _ => LocalizedErrorSummary.resolve(l10n, failure),
  };
}
