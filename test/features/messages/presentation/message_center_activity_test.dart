import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';
import 'package:y300/features/messages/presentation/widgets/message_feed_view.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';

void main() {
  testWidgets('background completion cannot prove an active message read', (
    tester,
  ) async {
    final reads = <Completer<DataReadResult<int, Object?>>>[];
    final completed = <int>[];
    final controller = MessageFeedController<int>(
      initialPage: 1,
      load: (_, _) {
        final result = Completer<DataReadResult<int, Object?>>();
        reads.add(result);
        return result.future;
      },
      nextPage: (_) => null,
      mergeMore: (_, next) => next,
      captureActiveRead: () => completed.add,
    );
    addTearDown(controller.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      LocalizedTestApp(
        home: MessageFeedView<int>(
          controller: controller,
          builder: (_, state) => Text('${state.data}'),
        ),
      ),
    );
    final initial = controller.refresh();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    reads.last.complete(
      const DataReadSuccess(
        data: 1,
        capabilities: null,
        metadata: DataReadMetadata.network(),
      ),
    );
    await initial;
    await tester.pump();
    expect(completed, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final visible = controller.refresh();
    reads.last.complete(
      const DataReadSuccess(
        data: 2,
        capabilities: null,
        metadata: DataReadMetadata.network(),
      ),
    );
    await visible;
    expect(completed, [2]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final initialTab in MessageCenterTab.values) {
    testWidgets(
      'hiding the shell during a ${initialTab.name} tab animation defers invalidation',
      (tester) async {
        final repository = MessageTestRepository();
        final container = ProviderContainer.test(
          overrides: [
            messageAttentionOwnerProvider.overrideWithValue(null),
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
