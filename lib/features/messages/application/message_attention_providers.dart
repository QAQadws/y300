import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_source.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';

/// In-memory evidence and local acknowledgement survive shell rebuilds.
final messageAttentionControllerProvider = Provider<MessageAttentionController>(
  (ref) {
    final controller = MessageAttentionController();
    ref.onDispose(controller.dispose);
    return controller;
  },
);

/// Authentication and source ownership are both required to accept evidence.
final messageAttentionOwnerProvider = Provider<MessageAttentionOwner?>((ref) {
  final owner = ref.watch(verifiedSessionOwnerProvider);
  final scope = ref.watch(yamiboForumSourceScopeProvider);
  if (owner == null ||
      !scope.isCurrent ||
      !scope.hasVerifiedIdentity ||
      scope.accountId != owner.uid) {
    return null;
  }
  return (sessionOwner: owner, sourceGeneration: scope.generation);
});

final messageAttentionStateProvider =
    NotifierProvider<MessageAttentionStateNotifier, MessageAttentionState>(
      MessageAttentionStateNotifier.new,
    );

/// Keeps the controller bound to the shared verified owner, outside client
/// construction. Watching authentication in the client factory would create a
/// cycle because authentication itself reads through that client.
final class MessageAttentionStateNotifier
    extends Notifier<MessageAttentionState> {
  @override
  MessageAttentionState build() {
    final controller = ref.watch(messageAttentionControllerProvider);
    controller.setOwner(ref.read(messageAttentionOwnerProvider));
    void publish() => state = controller.value;
    controller.addListener(publish);
    ref.listen(messageAttentionOwnerProvider, (_, owner) {
      controller.setOwner(owner);
    });
    ref.onDispose(() => controller.removeListener(publish));
    return controller.value;
  }
}
