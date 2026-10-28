import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/features/messages/application/message_attention_consumption_lifecycle.dart';
import 'package:y300/features/messages/application/message_attention_consumption_lifecycle_provider.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_test_repository.dart';

const _owner = (sessionOwner: (uid: '10', revision: 1), sourceGeneration: 1);
const _absent = ForumMessageAttentionState.absent;
const _present = ForumMessageAttentionState.present;
const _unknown = ForumMessageAttentionState.unknown;

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    for (final sample in [
      (name: 'messages', messages: _present, notifications: _absent),
      (name: 'notifications', messages: _absent, notifications: _present),
      (name: 'both', messages: _present, notifications: _present),
      (name: 'neither', messages: _absent, notifications: _absent),
    ]) {
      testWidgets('${sample.name} tab attention and semantics in $locale', (
        tester,
      ) async {
        final harness = _Harness();
        harness.accept(
          messages: sample.messages,
          notifications: sample.notifications,
        );
        await harness.pump(tester, locale: locale);
        harness.repository.reads.single.result.complete(messageTestPage([]));
        await tester.pumpAndSettle();

        _expectDots(
          tester,
          messages: sample.messages == _present,
          notifications: sample.notifications == _present,
        );
        // Showing category hints must not read the unvisited notification tab.
        expect(harness.repository.notificationReads, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('narrow scaled tabs keep labels stable in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final harness = _Harness();
      harness.accept(messages: _present, notifications: _present);
      await harness.pump(tester, locale: locale, brightness: Brightness.dark);
      harness.repository.reads.single.result.complete(messageTestPage([]));
      await tester.pumpAndSettle();
      final labels = _labels(tester);
      final positions = [
        for (final label in labels) tester.getRect(find.text(label)),
      ];
      final tabSize = tester.getSize(find.byType(TabBar));

      harness.accept(messages: _absent, notifications: _absent);
      await tester.pump();
      _expectDots(tester, messages: false, notifications: false);
      expect(tester.getSize(find.byType(TabBar)), tabSize);
      for (var index = 0; index < labels.length; index++) {
        expect(tester.getRect(find.text(labels[index])), positions[index]);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('aggregate-only attention never guesses a category', (
    tester,
  ) async {
    final harness = _Harness();
    harness.accept(aggregate: _present);
    await harness.pump(tester);
    harness.repository.reads.single.result.complete(messageTestPage([]));
    await tester.pumpAndSettle();
    expect(harness.attention.value.hasAttention, isTrue);
    _expectDots(tester, messages: false, notifications: false);
  });

  testWidgets('reading each tab waits for its own fresh remote calibration', (
    tester,
  ) async {
    final harness = _Harness();
    harness.accept(messages: _present, notifications: _present);
    await harness.pump(tester);
    final beforeRead = harness.attention.nextRequestSequence();
    harness.repository.reads.single.result.complete(messageTestPage([]));
    await tester.pumpAndSettle();
    expect(harness.calibrations, [beforeRead]);
    harness.attention.acknowledgeMore();
    await tester.pump();
    _expectDots(tester, messages: true, notifications: true);

    harness.accept(
      messages: _absent,
      notifications: _present,
      sequence: beforeRead,
    );
    await tester.pump();
    _expectDots(tester, messages: true, notifications: true);
    harness.accept(messages: _absent, notifications: _present);
    await tester.pump();
    _expectDots(tester, messages: false, notifications: true);

    await tester.tap(find.text(_labels(tester)[1]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(kTabScrollDuration);
    await tester.pump();
    expect(harness.repository.notificationReads, hasLength(1));
    _expectDots(tester, messages: false, notifications: true);
    harness.repository.notificationReads.single.result.complete(
      notificationTestPage([]),
    );
    await tester.pumpAndSettle();
    expect(harness.calibrations, hasLength(2));
    _expectDots(tester, messages: false, notifications: true);

    harness.accept(messages: _absent, notifications: _absent);
    await tester.pump();
    _expectDots(tester, messages: false, notifications: false);
    expect(harness.attention.value.hasAttention, isFalse);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed notification reads retain the notification dot', (
    tester,
  ) async {
    final harness = _Harness();
    harness.accept(messages: _absent, notifications: _present);
    await harness.pump(tester, initialTab: MessageCenterTab.notifications);
    harness.repository.notificationReads.single.result.complete(
      const DataReadFailure(
        kind: DataReadFailureKind.network,
        code: 'fixture_failure',
        diagnosticMessage: 'fixture_failure',
      ),
    );
    await tester.pumpAndSettle();
    _expectDots(tester, messages: false, notifications: true);
    expect(harness.calibrations, isEmpty);
  });

  testWidgets('another account cannot supply the current mailbox tab dots', (
    tester,
  ) async {
    final harness = _Harness();
    harness.accept(messages: _present, notifications: _present);
    await harness.pump(tester);
    harness.repository.reads.single.result.complete(messageTestPage([]));
    await tester.pumpAndSettle();
    _expectDots(tester, messages: true, notifications: true);

    harness.attention.setOwner(null);
    await tester.pump();
    _expectDots(tester, messages: false, notifications: false);
    const otherOwner = (
      sessionOwner: (uid: '11', revision: 2),
      sourceGeneration: 2,
    );
    harness.attention.setOwner(otherOwner);
    harness.attention.accept(
      const ForumMessageAttentionObservation(
        viewerUserId: '11',
        source: ForumMessageAttentionSource.api,
        privateMessages: _present,
        notifications: _present,
      ),
      owner: otherOwner,
      sequence: harness.attention.nextRequestSequence(),
    );
    await tester.pump();
    _expectDots(tester, messages: false, notifications: false);
  });
}

List<String> _labels(WidgetTester tester) {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(MessageCenterPage)),
  );
  return [l10n.messageMessagesTab, l10n.messageNotificationsTab];
}

void _expectDots(
  WidgetTester tester, {
  required bool messages,
  required bool notifications,
}) {
  final labels = _labels(tester);
  final l10n = AppLocalizations.of(
    tester.element(find.byType(MessageCenterPage)),
  );
  for (var index = 0; index < labels.length; index++) {
    final tab = find.ancestor(
      of: find.text(labels[index]),
      matching: find.byType(Tab),
    );
    final visible = index == 0 ? messages : notifications;
    final badge = tester.widget<Badge>(
      find.descendant(of: tab, matching: find.byType(Badge)),
    );
    expect(badge.isLabelVisible, visible);
    final node = tester.getSemantics(tab);
    final data = node.getSemanticsData();
    expect(data.label, contains(labels[index]));
    expect(data.hint, visible ? l10n.messageAttentionAvailable : isEmpty);
    expect(node.childrenCountInTraversalOrder, 0);
  }
}

final class _Harness {
  final repository = MessageTestRepository();
  final calibrations = <int>[];
  late final container = ProviderContainer.test(
    overrides: [
      messageAttentionOwnerProvider.overrideWithValue(_owner),
      messageAccountIdProvider.overrideWithValue('10'),
      messageRepositoryProvider.overrideWithValue(repository),
      messageAttentionConsumptionLifecycleProvider.overrideWith((ref) {
        return MessageAttentionConsumptionLifecycle(
          controller: ref.read(messageAttentionControllerProvider),
          readOwner: () => _owner,
          requestCalibration: (_, sequence) => calibrations.add(sequence),
        );
      }),
    ],
  );
  late final attention = container.read(messageAttentionControllerProvider);

  _Harness() {
    container.read(messageAttentionStateProvider);
  }

  void accept({
    ForumMessageAttentionState messages = _unknown,
    ForumMessageAttentionState notifications = _unknown,
    ForumMessageAttentionState aggregate = _unknown,
    int? sequence,
  }) => attention.accept(
    ForumMessageAttentionObservation(
      viewerUserId: '10',
      source: aggregate == _unknown
          ? ForumMessageAttentionSource.api
          : ForumMessageAttentionSource.mobileHtml,
      privateMessages: messages,
      notifications: notifications,
      combinedHint: aggregate,
    ),
    owner: _owner,
    sequence: sequence ?? attention.nextRequestSequence(),
  );

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    Brightness brightness = Brightness.light,
    MessageCenterTab initialTab = MessageCenterTab.messages,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          locale: locale,
          theme: ThemeData(brightness: brightness),
          home: MessageCenterDestination(initialTab: initialTab),
        ),
      ),
    );
    await tester.pump();
  }
}
