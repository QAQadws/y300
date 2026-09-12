import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A form opened for one actor must not survive an account switch. Replacing
/// the child disposes its platform view instead of covering a live old form.
class ForumWebViewAccountGuard extends ConsumerStatefulWidget {
  const ForumWebViewAccountGuard({
    super.key,
    required this.accountId,
    required this.builder,
  });

  final String accountId;
  final WidgetBuilder builder;

  @override
  ConsumerState<ForumWebViewAccountGuard> createState() =>
      _ForumWebViewAccountGuardState();
}

class _ForumWebViewAccountGuardState
    extends ConsumerState<ForumWebViewAccountGuard> {
  bool _opened = false;
  bool _expired = false;

  @override
  void didUpdateWidget(covariant ForumWebViewAccountGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId) _expired = true;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionControllerProvider);
    final identity = session.value;
    final matches =
        identity?.isLoggedIn == true &&
        !identity!.isLoggingOut &&
        identity.uid == widget.accountId;
    if (!matches && (_opened || !session.isLoading)) _expired = true;
    if (!_expired && matches) {
      _opened = true;
      return widget.builder(context);
    }
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _expired
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.forumWebViewAccountChanged,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(l10n.commonClose),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
