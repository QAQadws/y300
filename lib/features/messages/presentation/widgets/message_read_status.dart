import 'package:flutter/material.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class MessageReadStatus extends StatelessWidget {
  const MessageReadStatus({
    super.key,
    required this.failure,
    required this.onRetry,
  });
  final DataReadFailure<dynamic, dynamic>? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = failure;
    if (error == null) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error.code == 'message_history_changed'
                ? l10n.messageHistoryChanged
                : LocalizedErrorSummary.resolve(l10n, error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}

class MessageLoginPrompt extends StatelessWidget {
  const MessageLoginPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_unread_outlined, size: 40),
            const SizedBox(height: 16),
            Text(l10n.messageLoginRequired, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
              ),
              child: Text(l10n.authLoginTitle),
            ),
          ],
        ),
      ),
    );
  }
}

String messageTimeLabel(BuildContext context, DateTime? time, String fallback) {
  if (time == null) return fallback;
  final local = time.toLocal();
  final l10n = MaterialLocalizations.of(context);
  return '${l10n.formatMediumDate(local)} · ${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}
