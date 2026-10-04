import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/l10n/app_localizations.dart';

/// The managed self-profile WebView can opt into this native route action.
class MyProfileWebViewAction extends ConsumerStatefulWidget {
  const MyProfileWebViewAction({super.key, required this.currentUri});

  final Uri currentUri;

  @override
  ConsumerState<MyProfileWebViewAction> createState() =>
      _MyProfileWebViewActionState();
}

class _MyProfileWebViewActionState
    extends ConsumerState<MyProfileWebViewAction> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(verifiedSessionOwnerProvider);
    final uri = widget.currentUri;
    final site = Uri.parse(AppConfig.siteBaseUrl);
    final parameters = uri.queryParametersAll;
    bool matches(String key, String value) =>
        parameters[key]?.length == 1 && parameters[key]!.single == value;
    // Hide the action on login redirects, other members' pages, or after an
    // account change. Native navigation always uses the verified session.
    if (owner == null ||
        uri.scheme != site.scheme ||
        uri.host != site.host ||
        uri.port != site.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/home.php' ||
        !matches('mod', 'space') ||
        !matches('do', 'profile') ||
        !matches('uid', owner.uid)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const Key('forum-webview-native-profile-button'),
      tooltip: AppLocalizations.of(context).profileOpenNative,
      icon: const Icon(Icons.person_outline),
      onPressed: _opening ? null : () => _open(owner),
    );
  }

  Future<void> _open(VerifiedSessionOwner owner) async {
    if (_opening || ref.read(verifiedSessionOwnerProvider) != owner) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const MyProfilePage()),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
