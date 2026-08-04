import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/waf/waf_challenge_recovery_coordinator.dart';
import 'package:y300/features/forum/presentation/webview/waf_challenge_webview_page.dart';

typedef WafChallengePageBuilder =
    Widget Function(WafChallengeRecoveryRequest request);

final wafChallengePageBuilderProvider = Provider<WafChallengePageBuilder>((
  ref,
) {
  return (request) => WafChallengeWebViewPage(
    initialUri: _safeVerificationUri,
    userAgent: request.userAgent,
  );
});

final Uri _safeVerificationUri = Uri.parse(AppConfig.siteBaseUrl).replace(
  path: '/index.php',
  queryParameters: const <String, String>{'mobile': '2'},
  fragment: '',
);

/// Root navigation bridge for transport-triggered, foreground-only recovery.
class WafChallengeRecoveryHost extends ConsumerStatefulWidget {
  const WafChallengeRecoveryHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WafChallengeRecoveryHost> createState() =>
      _WafChallengeRecoveryHostState();
}

class _WafChallengeRecoveryHostState
    extends ConsumerState<WafChallengeRecoveryHost>
    with WidgetsBindingObserver {
  WafChallengeRecoveryDetach? _detachLauncher;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _detachLauncher = ref
        .read(wafChallengeRecoveryCoordinatorProvider)
        .attachLauncher(_launchVerification);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _detachLauncher?.call();
    _detachLauncher = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<WafChallengeRecoveryResult> _launchVerification(
    WafChallengeRecoveryRequest request,
  ) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted || !_isForeground) {
      return WafChallengeRecoveryResult.unavailable;
    }
    final page = ref.read(wafChallengePageBuilderProvider).call(request);
    final result = await Navigator.of(context, rootNavigator: true)
        .push<WafChallengeRecoveryResult>(
          MaterialPageRoute<WafChallengeRecoveryResult>(
            settings: const RouteSettings(
              name: WafChallengeWebViewPage.routeName,
            ),
            fullscreenDialog: true,
            builder: (_) => page,
          ),
        );
    return result ?? WafChallengeRecoveryResult.cancelled;
  }
}
