import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';

void main() {
  for (final initialTab in MessageCenterTab.values) {
    testWidgets(
      'hiding the shell during a ${initialTab.name} tab animation defers invalidation',
      (tester) async {
        final repository = MessageTestRepository();
        final container = ProviderContainer.test(
          overrides: [
            messageAccountIdProvider.overrideWithValue('10'),
            messageRepositoryProvider.overrideWithValue(repository),
          ],
        );
        var active = true;
        late StateSetter updateShell;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: LocalizedTestApp(
              home: StatefulBuilder(
                builder: (context, setState) {
                  updateShell = setState;
                  // Match the main shell: both the retained page's activity
                  // and its ancestor ticker mode change when switching away.
                  return IndexedStack(
                    index: active ? 0 : 1,
                    children: [
                      TickerMode(
                        enabled: active,
                        child: MessageCenterPage(
                          initialTab: initialTab,
                          isActive: active,
                          onOpenConversation: (_, _, _) {},
                          onOpenLink: (_, _) {},
                          onOpenUser: (_, _) {},
                        ),
                      ),
                      const SizedBox.expand(),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        void completePendingReads() {
          for (final read in repository.reads) {
            if (!read.result.isCompleted) {
              read.result.complete(messageTestPage([]));
            }
          }
          for (final read in repository.notificationReads) {
            if (!read.result.isCompleted) {
              read.result.complete(notificationTestPage([]));
            }
          }
        }

        completePendingReads();
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(MessageCenterPage)),
        );
        await tester.tap(
          find.text(
            initialTab == MessageCenterTab.messages
                ? l10n.messageNotificationsTab
                : l10n.messageMessagesTab,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final tabs = tester.widget<TabBar>(find.byType(TabBar)).controller!;
        expect(tabs.indexIsChanging, isTrue);
        completePendingReads();
        await tester.pump();

        final messagesBefore = repository.reads.length;
        final notificationsBefore = repository.notificationReads.length;
        updateShell(() => active = false);
        await tester.pump();
        final bus = container.read(messageRefreshBusProvider);
        for (final kind in MessageRefreshKind.values) {
          bus.publish(MessageRefreshEvent(accountId: '10', kind: kind));
        }
        await tester.pump(const Duration(milliseconds: 400));

        expect(repository.reads, hasLength(messagesBefore));
        expect(repository.notificationReads, hasLength(notificationsBefore));

        updateShell(() => active = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(kTabScrollDuration);
        await tester.pump();
        completePendingReads();
        await tester.pumpAndSettle();
        expect(tabs.index, 1 - initialTab.index);
        expect(
          initialTab == MessageCenterTab.messages
              ? repository.notificationReads.length
              : repository.reads.length,
          (initialTab == MessageCenterTab.messages
                  ? notificationsBefore
                  : messagesBefore) +
              1,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
