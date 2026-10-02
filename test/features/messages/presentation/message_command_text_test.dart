import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/presentation/message_command_text.dart';
import 'package:y300/l10n/app_localizations.dart';

void main() {
  for (final locale in [const Locale('zh'), const Locale('zh', 'TW')]) {
    test(
      'batch friend restriction uses safe localized text in $locale',
      () async {
        final strings = await AppLocalizations.delegate.load(locale);
        const result = DataCommandRejected<ForumPrivateMessageBatchReceipt>(
          DataCommandFailure(
            kind: DataCommandFailureKind.validation,
            retryPolicy: DataCommandRetryPolicy.afterInputChange,
            code: 'message_can_not_send_3',
            diagnosticMessage: 'untrusted-private-server-payload',
          ),
        );
        expect(
          privateMessageCommandText(strings, result),
          strings.messageBatchOnlyFriends,
        );
      },
    );
  }
}
