import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

/// The dialog owns one explicit write, even if the originating row scrolls away.
class NotificationIgnoreDialog extends ConsumerStatefulWidget {
  const NotificationIgnoreDialog({
    super.key,
    required this.accountId,
    required this.item,
  });
  final String accountId;
  final ForumNotificationItem item;

  @override
  ConsumerState<NotificationIgnoreDialog> createState() =>
      _NotificationIgnoreDialogState();
}

class _NotificationIgnoreDialogState
    extends ConsumerState<NotificationIgnoreDialog> {
  late ForumNotificationIgnoreScope _scope;
  bool _busy = false;
  DataCommandResult<ForumNotificationIgnoreReceipt>? _result;
  final _cancellation = ForumRequestCancellation();
  bool get _hasAuthor => RegExp(r'^[1-9]\d*$').hasMatch(widget.item.authorId);

  @override
  void initState() {
    super.initState();
    _scope = _hasAuthor
        ? ForumNotificationIgnoreScope.author
        : ForumNotificationIgnoreScope.allAuthors;
  }

  @override
  void dispose() {
    _cancellation.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || ref.read(messageAccountIdProvider) != widget.accountId) return;
    setState(() => _busy = true);
    DataCommandResult<ForumNotificationIgnoreReceipt> result;
    try {
      result = await ref
          .read(messageRepositoryProvider)
          .ignore(
            ForumNotificationIgnoreSubmission(
              notificationId: widget.item.id,
              type: widget.item.type,
              authorId: widget.item.authorId,
              scope: _scope,
              cancellation: _cancellation,
            ),
          );
    } on Object {
      result = const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          diagnosticMessage: 'notification_ignore_failed',
        ),
      );
    }
    if (!mounted || ref.read(messageAccountIdProvider) != widget.accountId) {
      return;
    }
    if (result case DataCommandApplied<ForumNotificationIgnoreReceipt>(
      :final receipt,
    )) {
      Navigator.of(context).pop(receipt);
    } else {
      setState(() {
        _busy = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ownsAccount = ref.watch(messageAccountIdProvider) == widget.accountId;
    final result = _result;
    return AlertDialog(
      title: Text(l10n.messageIgnore),
      scrollable: true,
      content: !ownsAccount
          ? Text(l10n.messageLoginRequired)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.messageIgnoreExplanation),
                const SizedBox(height: 12),
                RadioGroup<ForumNotificationIgnoreScope>(
                  groupValue: _scope,
                  onChanged: (scope) {
                    if (!_busy && scope != null) setState(() => _scope = scope);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasAuthor)
                        RadioListTile<ForumNotificationIgnoreScope>(
                          value: ForumNotificationIgnoreScope.author,
                          enabled: !_busy,
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.messageIgnoreAuthor),
                          subtitle: widget.item.authorName.isEmpty
                              ? null
                              : Text(widget.item.authorName),
                        ),
                      RadioListTile<ForumNotificationIgnoreScope>(
                        value: ForumNotificationIgnoreScope.allAuthors,
                        enabled: !_busy,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.messageIgnoreEveryone),
                      ),
                    ],
                  ),
                ),
                if (result?.failureOrNull != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      result is DataCommandOutcomeUnknown
                          ? l10n.messageIgnoreUnknown
                          : LocalizedErrorSummary.resolve(l10n, result),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
        if (ownsAccount)
          FilledButton(
            key: const Key('notification-ignore-save'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? l10n.messageIgnoreSaving : l10n.commonConfirm),
          ),
      ],
    );
  }
}
