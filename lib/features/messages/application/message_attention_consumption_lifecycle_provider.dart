import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/messages/application/message_attention_consumption_lifecycle.dart';
import 'package:y300/features/messages/application/message_attention_probe_runtime_provider.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';

final messageAttentionConsumptionLifecycleProvider =
    Provider<MessageAttentionConsumptionLifecycle>((ref) {
      final controller = ref.watch(messageAttentionControllerProvider);
      return MessageAttentionConsumptionLifecycle(
        controller: controller,
        readOwner: () {
          if (controller.value.owner == null) return null;
          return ref.read(messageAttentionOwnerProvider);
        },
        requestCalibration: (owner, minimumSequence) => ref
            .read(messageAttentionProbeRuntimeProvider)
            .requestCalibration(owner, minimumSequence),
      );
    });
