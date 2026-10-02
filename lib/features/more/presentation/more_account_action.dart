import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';

class MoreAccountAction extends ConsumerWidget {
  const MoreAccountAction({
    super.key,
    required this.onLogin,
    required this.onLogout,
    this.isPending = false,
  });

  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final bool isPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionControllerProvider);
    final session = auth.asData?.value;
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final signedIn = session?.isLoggedIn == true;
    final loggingOut = session?.isLoggingOut == true;
    final busy =
        isPending ||
        auth.isLoading ||
        loggingOut ||
        (signedIn && owner == null);
    final l10n = AppLocalizations.of(context);

    if (signedIn) {
      return IconButton(
        key: const Key('more-logout-entry'),
        onPressed: busy ? null : onLogout,
        tooltip: l10n.moreLogout,
        icon: loggingOut
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout, size: 20),
      );
    }
    return TextButton.icon(
      key: const Key('more-login-entry'),
      onPressed: busy ? null : onLogin,
      icon: const Icon(Icons.login, size: 20),
      label: Text(l10n.moreLogin),
    );
  }
}
