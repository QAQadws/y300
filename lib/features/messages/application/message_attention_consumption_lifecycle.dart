import 'package:y300/features/messages/application/message_attention_controller.dart';

export 'message_attention_controller.dart'
    show MessageAttentionConsumptionKind, MessageAttentionOwner;

/// Receives accepted active business reads, independently from feed refreshes.
final class MessageAttentionConsumptionLifecycle {
  MessageAttentionConsumptionLifecycle({
    required MessageAttentionController controller,
    required MessageAttentionOwner? Function() readOwner,
    required void Function(MessageAttentionOwner owner, int minimumSequence)
    requestCalibration,
  }) : _controller = controller,
       _readOwner = readOwner,
       _requestCalibration = requestCalibration;

  final MessageAttentionController _controller;
  final MessageAttentionOwner? Function() _readOwner;
  final void Function(MessageAttentionOwner owner, int minimumSequence)
  _requestCalibration;

  MessageAttentionOwner? captureOwner() {
    final owner = _readOwner();
    return owner != null && owner == _controller.value.owner ? owner : null;
  }

  void onReadSucceeded({
    required MessageAttentionOwner owner,
    required MessageAttentionConsumptionKind kind,
  }) {
    if (_readOwner() != owner) return;
    final barrier = _controller.recordConsumption(owner: owner, kind: kind);
    if (barrier != null) _requestCalibration(owner, barrier);
  }
}
