import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/app/startup/message_attention_probe_host.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/messages/application/message_attention_consumption_lifecycle_provider.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';
import 'package:y300/features/messages/application/message_attention_probe_runtime_provider.dart';
import 'package:y300/features/messages/application/message_attention_probe_coordinator.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';

const _owner = (sessionOwner: (uid: '42', revision: 1), sourceGeneration: 3);
const _delay = Duration(milliseconds: 10);

void main() {
  testWidgets(
    'root host calibrates once, defers background and rejects its late result',
    (tester) async {
      final repository = _AttentionRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MessageAttentionProbeHost(child: SizedBox()),
        ),
      );
      await tester.pump(_delay);
      expect(repository.reads, hasLength(1));
      expect(repository.reads.single.$1.expectedUserId, '42');
      repository.complete(0, ForumMessageAttentionState.absent);
      await tester.pump();
      final controller = container.read(messageAttentionControllerProvider);
      expect(controller.latestCompleteSequence, 1);
      expect(controller.value.hasAttention, isFalse);

      container
          .read(messageAttentionConsumptionLifecycleProvider)
          .onReadSucceeded(
            owner: _owner,
            kind: MessageAttentionConsumptionKind.privateMessages,
          );
      await tester.pump(_delay);
      expect(repository.reads, hasLength(2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(repository.reads.last.$1.cancellation!.isCancelled, isTrue);
      repository.complete(1, ForumMessageAttentionState.present);
      await tester.pump();
      expect(controller.value.hasAttention, isFalse);
      await tester.pump(const Duration(minutes: 3));
      expect(repository.reads, hasLength(2));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(_delay);
      expect(repository.reads, hasLength(3));
      repository.complete(2, ForumMessageAttentionState.present);
      await tester.pump();
      expect(controller.value.hasAttention, isTrue);
      expect(controller.latestCompleteSequence, 3);
      await tester.pump(const Duration(minutes: 5));
      expect(repository.reads, hasLength(3));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ordinary complete samples suppress pending probes, partial samples do not',
    (tester) async {
      final repository = _AttentionRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MessageAttentionProbeHost(child: SizedBox()),
        ),
      );
      final controller = container.read(messageAttentionControllerProvider);
      controller.accept(
        const ForumMessageAttentionObservation(
          viewerUserId: '42',
          source: ForumMessageAttentionSource.mobileHtml,
          combinedHint: ForumMessageAttentionState.present,
        ),
        owner: _owner,
        sequence: controller.nextRequestSequence(),
      );
      await tester.pump(_delay);
      expect(repository.reads, isEmpty);
      container
          .read(messageAttentionConsumptionLifecycleProvider)
          .onReadSucceeded(
            owner: _owner,
            kind: MessageAttentionConsumptionKind.privateMessages,
          );
      controller.accept(
        const ForumMessageAttentionObservation(
          viewerUserId: '42',
          source: ForumMessageAttentionSource.api,
          notifications: ForumMessageAttentionState.absent,
        ),
        owner: _owner,
        sequence: controller.nextRequestSequence(),
      );
      await tester.pump(_delay);
      expect(repository.reads, hasLength(1));
      repository.complete(0, ForumMessageAttentionState.absent);
      await tester.pump();
      expect(controller.value.hasAttention, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'new owner rejects the old probe and gets an independent opportunity',
    (tester) async {
      final repository = _AttentionRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MessageAttentionProbeHost(child: SizedBox()),
        ),
      );
      await tester.pump(_delay);
      const nextOwner = (
        sessionOwner: (uid: '42', revision: 2),
        sourceGeneration: 4,
      );
      container.updateOverrides([
        messageAttentionOwnerProvider.overrideWithValue(nextOwner),
        messageAttentionProbePolicyProvider.overrideWithValue(
          container.read(messageAttentionProbePolicyProvider),
        ),
        yamiboForumClientProvider.overrideWithValue(
          container.read(yamiboForumClientProvider),
        ),
      ]);
      await container.pump();
      expect(repository.reads.first.$1.cancellation!.isCancelled, isTrue);
      repository.complete(0, ForumMessageAttentionState.present);
      await tester.pump();
      expect(
        container.read(messageAttentionControllerProvider).value.hasAttention,
        isFalse,
      );
      await tester.pump(_delay);
      expect(repository.reads, hasLength(2));
      repository.complete(1, ForumMessageAttentionState.absent);
      await tester.pump();
      expect(
        container.read(messageAttentionControllerProvider).value.owner,
        nextOwner,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

ProviderContainer _container(_AttentionRepository repository) =>
    ProviderContainer(
      overrides: [
        messageAttentionOwnerProvider.overrideWithValue(_owner),
        messageAttentionProbePolicyProvider.overrideWithValue(
          const MessageAttentionProbePolicy(coalesceDelay: _delay),
        ),
        yamiboForumClientProvider.overrideWithValue(
          YamiboForumClient(
            config: ForumClientConfig.yamibo(),
            network: _UnusedNetwork(),
            sourcePlan: ForumClientSourcePlan(messageAttention: repository),
          ),
        ),
      ],
    );

final class _UnusedNetwork implements ForumClientNetwork {
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) => throw StateError('facade repository must be used');
}

final class _AttentionRepository implements ForumMessageAttentionRepository {
  final reads =
      <
        (
          ForumMessageAttentionQuery,
          Completer<
            DataReadResult<
              ForumMessageAttentionObservation,
              ForumMessageAttentionReadCapabilities
            >
          >,
        )
      >[];

  @override
  ForumMessageAttentionSourceCapabilities get capabilities =>
      ForumMessageAttentionSourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumMessageAttentionCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<
      ForumMessageAttentionObservation,
      ForumMessageAttentionReadCapabilities
    >
  >
  load(ForumMessageAttentionQuery query) {
    final result =
        Completer<
          DataReadResult<
            ForumMessageAttentionObservation,
            ForumMessageAttentionReadCapabilities
          >
        >();
    reads.add((query, result));
    return result.future;
  }

  void complete(int index, ForumMessageAttentionState value) =>
      reads[index].$2.complete(
        DataReadSuccess(
          data: ForumMessageAttentionObservation(
            viewerUserId: '42',
            source: ForumMessageAttentionSource.api,
            privateMessages: value,
            notifications: value,
          ),
          capabilities: ForumMessageAttentionReadCapabilities(
            values: DataCapabilitySet.supported(
              ForumMessageAttentionCapability.values,
            ),
          ),
          metadata: const DataReadMetadata.network(),
        ),
      );
}
