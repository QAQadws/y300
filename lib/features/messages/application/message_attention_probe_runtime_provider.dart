import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';
import 'package:y300/features/messages/application/message_attention_probe_coordinator.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';

/// Periodic probing is disabled by default; composition can opt in explicitly.
final messageAttentionProbePolicyProvider =
    Provider<MessageAttentionProbePolicy>(
      (ref) => const MessageAttentionProbePolicy(),
    );

final messageAttentionProbeRuntimeProvider =
    Provider<MessageAttentionProbeRuntime>((ref) {
      final controller = ref.watch(messageAttentionControllerProvider);
      final coordinator = MessageAttentionProbeCoordinator(
        policy: ref.watch(messageAttentionProbePolicyProvider),
        probe: (owner, cancellation) async {
          if (!ref.mounted ||
              cancellation.isCancelled ||
              ref.read(messageAttentionOwnerProvider) != owner) {
            return false;
          }
          final sequence = controller.nextRequestSequence();
          final result = await ref
              .read(yamiboForumClientProvider)
              .loadMessageAttention(
                ForumMessageAttentionQuery(
                  expectedUserId: owner.sessionOwner.uid,
                  cancellation: cancellation,
                ),
              );
          if (!ref.mounted ||
              cancellation.isCancelled ||
              ref.read(messageAttentionOwnerProvider) != owner ||
              result
                  is! DataReadSuccess<
                    ForumMessageAttentionObservation,
                    ForumMessageAttentionReadCapabilities
                  > ||
              result.metadata.origin != DataReadOrigin.network ||
              result.metadata.freshness != DataReadFreshness.current) {
            return false;
          }
          // The explicit probe is excluded from passive transport publication;
          // one captured sequence is applied exactly once at this boundary.
          controller.accept(result.data, owner: owner, sequence: sequence);
          return controller.latestCompleteSequence == sequence;
        },
      );
      final runtime = MessageAttentionProbeRuntime(coordinator);
      final subscription = controller.freshSamples.listen((sample) {
        coordinator.recordFreshSample(
          owner: sample.owner,
          sequence: sample.sequence,
        );
      });
      ref.listen(messageAttentionOwnerProvider, (_, owner) {
        controller.setOwner(owner);
        runtime.updateOwner(owner);
      }, fireImmediately: true);
      ref.onDispose(() {
        runtime.dispose();
        unawaited(subscription.cancel());
      });
      return runtime;
    });

/// Provider-container ownership outlives individual shell and route widgets.
final class MessageAttentionProbeRuntime {
  MessageAttentionProbeRuntime(this.coordinator);

  final MessageAttentionProbeCoordinator coordinator;
  final Set<Object> _foregroundHosts = Set.identity();
  MessageAttentionOwner? _owner;
  bool _disposed = false;

  void updateOwner(MessageAttentionOwner? owner) {
    if (_disposed) return;
    _owner = owner;
    _reconcile();
  }

  void setForeground(bool foreground, {required Object host}) {
    if (_disposed) return;
    if (foreground) {
      _foregroundHosts.add(host);
    } else {
      _foregroundHosts.remove(host);
    }
    _reconcile();
  }

  void _reconcile() => coordinator.setEligibility(
    owner: _owner,
    foreground: _foregroundHosts.isNotEmpty,
  );

  void requestCalibration(MessageAttentionOwner owner, int minimumSequence) {
    if (_disposed) return;
    coordinator.requestCalibration(
      owner: owner,
      minimumSequence: minimumSequence,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _foregroundHosts.clear();
    coordinator.dispose();
  }
}
