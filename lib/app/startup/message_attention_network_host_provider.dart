import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/startup/message_attention_network_host.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';

/// Stable host; owner lookup happens at send/receive time, never while building
/// the client or authenticating its first session.
final messageAttentionNetworkHostProvider =
    Provider<ForumMessageAttentionObserver>((ref) {
      final controller = ref.watch(messageAttentionControllerProvider);
      final host = MessageAttentionNetworkHost(
        controller: controller,
        readOwner: () {
          // The shell establishes verified ownership. Until then, authentication
          // reads must not recursively ask the authentication provider for it.
          if (controller.value.owner == null) return null;
          return ref.read(messageAttentionOwnerProvider);
        },
      );
      ref.onDispose(host.dispose);
      return host;
    });
