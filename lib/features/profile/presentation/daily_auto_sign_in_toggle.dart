import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_controller.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Loads only the account preference; displaying this control never checks
/// remote sign-in status or starts an automatic attempt.
class DailyAutoSignInToggle extends ConsumerWidget {
  const DailyAutoSignInToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(verifiedSessionOwnerProvider);
    final state = ref.watch(dailySignInControllerProvider);
    if (owner == null || state.owner != owner) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final canChange =
        state.autoEnabled != null &&
        !state.isSavingAutoPreference &&
        !state.settingsUnavailable;
    return MergeSemantics(
      child: Tooltip(
        message: state.settingsUnavailable
            ? l10n.dailyAutoSignInStorageUnavailable
            : state.isSavingAutoPreference
            ? l10n.dailyAutoSignInSaving
            : l10n.dailyAutoSignInDescription,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                l10n.dailyAutoSignInToggle,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (state.autoEnabled == null && !state.settingsUnavailable)
              // Reserve the adaptive control's space without showing an
              // invented off state. Mount the real switch only when known,
              // so its first frame does not animate from disabled to enabled.
              const Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Switch.adaptive(value: false, onChanged: null),
              )
            else
              Switch.adaptive(
                key: const Key('daily-auto-sign-in-toggle'),
                value: state.autoEnabled ?? false,
                onChanged: canChange
                    ? (value) => _setEnabled(context, ref, owner, value)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    VerifiedSessionOwner owner,
    bool value,
  ) async {
    if (ref.read(verifiedSessionOwnerProvider) != owner) return;
    await ref
        .read(dailySignInControllerProvider.notifier)
        .setAutomaticEnabled(value);
    if (!context.mounted || ref.read(verifiedSessionOwnerProvider) != owner) {
      return;
    }
    if (ref.read(dailySignInControllerProvider).settingsUnavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).dailyAutoSignInStorageUnavailable,
          ),
        ),
      );
    }
  }
}
