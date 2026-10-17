import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';

/// Binds package observations to the App's verified session and source scope.
/// No payload, credentials, or request state is persisted by this host.
final class MessageAttentionNetworkHost
    implements ForumMessageAttentionObserver {
  MessageAttentionNetworkHost({
    required MessageAttentionController controller,
    required MessageAttentionOwner? Function() readOwner,
  }) : _controller = controller,
       _readOwner = readOwner;

  final MessageAttentionController _controller;
  final MessageAttentionOwner? Function() _readOwner;
  bool _disposed = false;

  @override
  ForumMessageAttentionRequestContext? captureRequest() {
    if (_disposed) return null;
    final owner = _readOwner();
    if (owner == null) return null;
    return ForumMessageAttentionRequestContext(
      viewerUserId: owner.sessionOwner.uid,
      requestSequence: _controller.nextRequestSequence(),
      ownerToken: owner,
    );
  }

  @override
  void onObservation(
    ForumMessageAttentionObservation observation, {
    required ForumMessageAttentionRequestContext context,
  }) {
    if (_disposed) return;
    final owner = _readOwner();
    _controller.setOwner(owner);
    if (owner == null ||
        context.ownerToken is! MessageAttentionOwner ||
        context.ownerToken != owner ||
        context.viewerUserId != owner.sessionOwner.uid ||
        observation.viewerUserId != owner.sessionOwner.uid) {
      return;
    }
    _controller.accept(
      observation,
      owner: owner,
      sequence: context.requestSequence,
    );
  }

  void dispose() => _disposed = true;
}
