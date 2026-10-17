import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/startup/message_attention_visibility_host.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';

import '../../test_support/localized_test_app.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('only actual More selection acknowledges the retained round', (
    tester,
  ) async {
    final fixture = _VisibilityFixture(selected: false);
    addTearDown(fixture.dispose);
    fixture.observe(ForumMessageAttentionState.present);
    await tester.pumpWidget(fixture.widget);
    await tester.pumpAndSettle();
    expect(fixture.attention.value.hasUnacknowledgedAttention, true);

    // Rebuilding a kept-alive but hidden page is not an entry event.
    await tester.pumpWidget(fixture.widget);
    await tester.pumpAndSettle();
    expect(fixture.attention.value.hasUnacknowledgedAttention, true);
    fixture.selected.value = true;
    await tester.pumpAndSettle();
    expect(fixture.attention.value.hasUnacknowledgedAttention, false);

    fixture.selected.value = false;
    await tester.pumpAndSettle();
    fixture.observe(ForumMessageAttentionState.present);
    expect(fixture.attention.value.hasUnacknowledgedAttention, false);
    fixture.observe(ForumMessageAttentionState.absent);
    fixture.observe(ForumMessageAttentionState.present);
    expect(fixture.attention.value.hasUnacknowledgedAttention, true);
  });

  testWidgets('visible More acknowledges new rounds without another tap', (
    tester,
  ) async {
    final fixture = _VisibilityFixture(selected: true);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.widget);
    await tester.pumpAndSettle();
    fixture.observe(ForumMessageAttentionState.present);
    expect(fixture.attention.value.hasUnacknowledgedAttention, false);
    fixture.observe(ForumMessageAttentionState.absent);
    fixture.observe(ForumMessageAttentionState.present);
    expect(fixture.attention.value.hasUnacknowledgedAttention, false);
    expect(fixture.attention.value.hasAttention, true);
  });

  testWidgets('popup coverage and its reverse transition do not acknowledge', (
    tester,
  ) async {
    final fixture = _VisibilityFixture(selected: true);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.widget);
    await tester.pumpAndSettle();
    fixture.observe(ForumMessageAttentionState.present);
    unawaited(
      showDialog<void>(
        context: fixture.navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Overlay fixture')),
      ),
    );
    await tester.pumpAndSettle();
    fixture.observe(ForumMessageAttentionState.absent);
    fixture.observe(ForumMessageAttentionState.present);
    expect(fixture.attention.value.hasUnacknowledgedAttention, true);

    fixture.navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fixture.routes.isTransitioning, true);
    expect(fixture.attention.value.hasUnacknowledgedAttention, true);
    await tester.pumpAndSettle();
    expect(fixture.routes.isTransitioning, false);
    expect(fixture.attention.value.hasUnacknowledgedAttention, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background and covered page preserve new acknowledgement', (
    tester,
  ) async {
    final fixture = _VisibilityFixture(selected: true);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.widget);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fixture.observe(ForumMessageAttentionState.present);
    expect(fixture.attention.value.hasUnacknowledgedAttention, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.attention.value.hasUnacknowledgedAttention, false);

    unawaited(
      fixture.navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Page fixture')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    fixture.observe(ForumMessageAttentionState.absent);
    fixture.observe(ForumMessageAttentionState.present);
    expect(fixture.attention.value.hasUnacknowledgedAttention, true);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fixture.attention.value.hasUnacknowledgedAttention, false);
    expect(tester.takeException(), isNull);
  });
}

class _VisibilityFixture {
  _VisibilityFixture({required bool selected})
    : selected = ValueNotifier(selected) {
    attention.setOwner(owner);
  }

  static const MessageAttentionOwner owner = (
    sessionOwner: (uid: '101', revision: 0),
    sourceGeneration: 0,
  );

  final attention = MessageAttentionController();
  final routes = MessageAttentionRouteObserver();
  final navigator = GlobalKey<NavigatorState>();
  final ValueNotifier<bool> selected;

  void observe(ForumMessageAttentionState state) {
    attention.accept(
      ForumMessageAttentionObservation(
        viewerUserId: owner.sessionOwner.uid,
        source: ForumMessageAttentionSource.mobileHtml,
        combinedHint: state,
      ),
      owner: owner,
      sequence: attention.nextRequestSequence(),
    );
  }

  Widget get widget => ProviderScope(
    overrides: [
      messageAttentionControllerProvider.overrideWithValue(attention),
      messageAttentionOwnerProvider.overrideWithValue(owner),
      messageAttentionRouteObserverProvider.overrideWithValue(routes),
    ],
    child: LocalizedTestApp(
      navigatorKey: navigator,
      navigatorObservers: [routes],
      home: ValueListenableBuilder<bool>(
        valueListenable: selected,
        builder: (context, isMoreSelected, _) => MessageAttentionVisibilityHost(
          isMoreSelected: isMoreSelected,
          child: const Scaffold(body: Text('More fixture')),
        ),
      ),
    ),
  );

  void dispose() {
    attention.dispose();
    routes.dispose();
    selected.dispose();
  }
}
