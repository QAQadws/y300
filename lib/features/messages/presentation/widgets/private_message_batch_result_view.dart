import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/messages/presentation/private_message_batch_send_controller.dart';
import 'package:y300/l10n/app_localizations.dart';

/// The forum proves a batch write, never a delivered state for each row.
class PrivateMessageBatchResultView extends StatelessWidget {
  const PrivateMessageBatchResultView({
    super.key,
    required this.snapshot,
    required this.receipt,
    required this.onDone,
    required this.onSendAgain,
  });
  final PrivateMessageBatchSnapshot snapshot;
  final ForumPrivateMessageBatchReceipt receipt;
  final VoidCallback onDone;
  final VoidCallback? onSendAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final remaining = snapshot.usernames
        .where((name) => !receipt.excludedUsernames.contains(name))
        .toList();
    return ListView(
      key: const Key('message-batch-result'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.messageBatchResultTitle,
          style: theme.textTheme.titleLarge?.copyWith(color: palette.itemTitle),
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.messageBatchReportedAccepted(
              receipt.serverReportedAcceptedCount,
            ),
            style: TextStyle(color: palette.body),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.messageBatchResultCaution,
          style: TextStyle(color: palette.supportingText),
        ),
        if (receipt.excludedUsernames.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            l10n.messageBatchExcluded,
            style: theme.textTheme.titleSmall?.copyWith(
              color: palette.itemTitle,
            ),
          ),
          const SizedBox(height: 8),
          for (final name in receipt.excludedUsernames)
            Text(name, style: TextStyle(color: palette.body)),
        ],
        const SizedBox(height: 20),
        Text(
          l10n.messageBatchUnproven,
          style: theme.textTheme.titleSmall?.copyWith(color: palette.itemTitle),
        ),
        const SizedBox(height: 8),
        for (final name in remaining)
          Text(name, style: TextStyle(color: palette.body)),
        const SizedBox(height: 20),
        Text(
          l10n.messageBatchSubmittedMessage,
          style: theme.textTheme.titleSmall?.copyWith(color: palette.itemTitle),
        ),
        const SizedBox(height: 8),
        SelectableText(
          snapshot.message,
          style: theme.textTheme.bodyLarge?.copyWith(color: palette.body),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const Key('message-batch-send-again'),
          onPressed: onSendAgain,
          icon: const Icon(Icons.send_outlined),
          label: Text(l10n.messageBatchSendAgain, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('message-batch-done'),
          onPressed: onDone,
          child: Text(l10n.messageBatchDone),
        ),
      ],
    );
  }
}
