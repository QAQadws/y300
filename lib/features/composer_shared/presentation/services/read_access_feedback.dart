import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A proven write may still need a separate notice about the saved permission.
String? readAccessFeedback(
  AppLocalizations l10n,
  ThreadReadAccessEvidence? evidence,
) {
  if (evidence == null) return null;
  return switch (evidence.kind) {
    ThreadReadAccessEvidenceKind.serverAdjusted =>
      l10n.composerReadAccessAdjusted(evidence.requested, evidence.actual!),
    ThreadReadAccessEvidenceKind.unverified =>
      l10n.composerReadAccessUnverified(evidence.requested),
    _ => null,
  };
}
