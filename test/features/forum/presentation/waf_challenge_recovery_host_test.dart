import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/features/forum/presentation/webview/waf_challenge_recovery_host.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'opens one foreground verification route and returns its result',
    (tester) async {
      final coordinator = WafChallengeRecoveryCoordinator(
        retryCooldown: Duration.zero,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wafChallengeRecoveryCoordinatorProvider.overrideWithValue(
              coordinator,
            ),
            wafChallengePageBuilderProvider.overrideWithValue((_) {
              return Scaffold(
                key: const Key('fake-waf-verification-page'),
                body: Builder(
                  builder: (pageContext) {
                    return Center(
                      child: FilledButton(
                        key: const Key('complete-waf-verification'),
                        onPressed: () => Navigator.of(
                          pageContext,
                        ).pop(WafChallengeRecoveryResult.verified),
                        child: const Text('complete'),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
          child: const LocalizedTestApp(
            home: WafChallengeRecoveryHost(child: Scaffold(body: Text('home'))),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      final recovery = coordinator.recover(
        WafChallengeRecoveryRequest(
          triggeringUri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
          method: 'GET',
          evidence: WafChallengeEvidence.scriptBody,
          userAgent: 'test-agent',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('fake-waf-verification-page')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('complete-waf-verification')));
      await tester.pumpAndSettle();
      expect(await recovery, WafChallengeRecoveryResult.verified);
      expect(find.text('home'), findsOneWidget);
    },
  );
}
