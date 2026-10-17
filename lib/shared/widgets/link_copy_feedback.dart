import 'package:flutter/widgets.dart';
import 'package:y300/l10n/app_localizations.dart';

import 'transient_feedback.dart';

final _feedbackOwners = Expando<Object>('linkCopyFeedbackOwner');

/// Copies through the caller's shared writer and reports only current results.
Future<void> copyLinkWithFeedback(
  BuildContext context, {
  required String url,
  required Future<void> Function(String text) writeText,
  required bool Function() isCurrent,
}) async {
  if (!context.mounted || !isCurrent()) return;

  // Bubbles may provide different contexts within one route. Only its latest
  // copy reports feedback; already issued clipboard writes remain independent.
  final scope = ModalRoute.of(context) ?? context;
  final owner = Object();
  _feedbackOwners[scope] = owner;
  try {
    await writeText(url);
  } on Object {
    if (context.mounted &&
        isCurrent() &&
        identical(_feedbackOwners[scope], owner)) {
      showTransientSnackBar(
        context,
        AppLocalizations.of(context).linkCopyFailed,
      );
    }
    return;
  }
  if (context.mounted &&
      isCurrent() &&
      identical(_feedbackOwners[scope], owner)) {
    showTransientSnackBar(context, AppLocalizations.of(context).linkCopied);
  }
}
