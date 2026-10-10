import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/presentation/services/thread_post_navigation.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  for (final successful in [true, false]) {
    testWidgets(
      'explicit thread Copy ${successful ? 'records successful evidence' : 'preserves write failure without evidence'}',
      (tester) async {
        final completion = Completer<void>();
        final writes = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.getData') {
            fail('Copy must not read the clipboard');
          }
          if (call.method == 'Clipboard.setData') {
            writes.add((call.arguments as Map)['text'] as String);
            await completion.future;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final session = ThreadPostNavigationSession();
        addTearDown(session.dispose);
        late ThreadPostNavigation navigation;
        late BuildContext source;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: LocalizedTestApp(
              home: Consumer(
                builder: (context, ref, _) {
                  source = context;
                  navigation = ThreadPostNavigation(
                    context: context,
                    ref: ref,
                    tid: '1',
                    imageReferer: null,
                    isCurrent: () => context.mounted,
                    routeSession: session,
                  );
                  return const Scaffold(body: Text('Thread Copy'));
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        const url = 'https://bbs.yamibo.com/thread-1-2-1.html#pid3';
        final registry = container.read(
          clipboardSelfCopyFingerprintRegistryProvider,
        );
        final l10n = AppLocalizations.of(source);
        final pending = navigation.copyUrl(
          l10n.threadDetailCopyLink,
          '  $url  ',
        );
        await tester.idle();
        expect(writes, [url]);
        expect(registry.containsText(url), isFalse);
        expect(find.byType(SnackBar), findsNothing);
        if (successful) {
          completion.complete();
          await pending;
        } else {
          final result = expectLater(
            pending,
            throwsA(isA<PlatformException>()),
          );
          completion.completeError(PlatformException(code: 'write_failed'));
          await result;
        }
        await tester.pumpAndSettle();
        expect(registry.containsText(url), successful);
        expect(writes, [url]);
        expect(
          find.text(l10n.threadDetailCopySuccess(l10n.threadDetailCopyLink)),
          successful ? findsOneWidget : findsNothing,
        );
      },
    );
  }
}
