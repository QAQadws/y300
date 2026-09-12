import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/widgets/message_read_status.dart';
import 'package:y300/features/messages/presentation/widgets/private_message_editor.dart';
import 'package:y300/l10n/app_localizations.dart';

class NewPrivateMessagePage extends ConsumerWidget {
  const NewPrivateMessagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(messageAccountIdProvider);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).y300NativeContent.background,
      appBar: AppBar(title: Text(l10n.messageNew)),
      body: account == null
          ? const MessageLoginPrompt()
          : PrivateMessageEditor(
              key: ValueKey(account),
              accountId: account,
              onApplied: (_) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.messageSent)));
                // The receipt identifies the username, not its UID. The directory
                // refresh resolves the real conversation without guessing identity.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted &&
                      (ModalRoute.isCurrentOf(context) ?? false)) {
                    Navigator.of(context).pop();
                  }
                });
              },
            ),
    );
  }
}
