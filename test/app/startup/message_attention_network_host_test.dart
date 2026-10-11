import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/startup/message_attention_network_host.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';

const _owner = (sessionOwner: (uid: '42', revision: 1), sourceGeneration: 2);

ForumMessageAttentionObservation _observation(
  ForumMessageAttentionState state, {
  String userId = '42',
}) => ForumMessageAttentionObservation(
  viewerUserId: userId,
  source: ForumMessageAttentionSource.mobileHtml,
  combinedHint: state,
);

void main() {
  test('capture is optional until an owner is verified', () {
    MessageAttentionOwner? owner;
    final controller = MessageAttentionController();
    final host = MessageAttentionNetworkHost(
      controller: controller,
      readOwner: () => owner,
    );
    addTearDown(controller.dispose);
    expect(host.captureRequest(), isNull);
    owner = _owner;
    final context = host.captureRequest()!;
    expect(context.viewerUserId, '42');
    expect(context.ownerToken, _owner);
    expect(context.requestSequence, 1);
  });

  test('request order is shared across rebuilt hosts', () {
    final controller = MessageAttentionController();
    addTearDown(controller.dispose);
    final first = MessageAttentionNetworkHost(
      controller: controller,
      readOwner: () => _owner,
    );
    final older = first.captureRequest()!;
    first.dispose();
    final second = MessageAttentionNetworkHost(
      controller: controller,
      readOwner: () => _owner,
    );
    final newer = second.captureRequest()!;
    expect(newer.requestSequence, greaterThan(older.requestSequence));
    second.onObservation(
      _observation(ForumMessageAttentionState.absent),
      context: newer,
    );
    second.onObservation(
      _observation(ForumMessageAttentionState.present),
      context: older,
    );
    expect(controller.value.combined, ForumMessageAttentionState.absent);
  });

  for (final replacement in <MessageAttentionOwner?>[
    null,
    (sessionOwner: (uid: '99', revision: 1), sourceGeneration: 2),
    (sessionOwner: (uid: '42', revision: 2), sourceGeneration: 2),
    (sessionOwner: (uid: '42', revision: 1), sourceGeneration: 3),
  ]) {
    test('late evidence cannot cross ownership change $replacement', () {
      MessageAttentionOwner? owner = _owner;
      final controller = MessageAttentionController();
      addTearDown(controller.dispose);
      final host = MessageAttentionNetworkHost(
        controller: controller,
        readOwner: () => owner,
      );
      final context = host.captureRequest()!;
      host.onObservation(
        _observation(ForumMessageAttentionState.present),
        context: context,
      );
      expect(controller.value.hasAttention, isTrue);
      owner = replacement;
      host.onObservation(
        _observation(ForumMessageAttentionState.present),
        context: context,
      );
      expect(controller.value.owner, replacement);
      expect(controller.value.hasAttention, isFalse);
      expect(controller.value.attentionEpoch, 0);
    });
  }

  test('context and response viewer must both match the captured owner', () {
    final controller = MessageAttentionController();
    addTearDown(controller.dispose);
    final host = MessageAttentionNetworkHost(
      controller: controller,
      readOwner: () => _owner,
    );
    host.onObservation(
      _observation(ForumMessageAttentionState.present, userId: '99'),
      context: host.captureRequest()!,
    );
    host.onObservation(
      _observation(ForumMessageAttentionState.present),
      context: const ForumMessageAttentionRequestContext(
        viewerUserId: '99',
        requestSequence: 2,
        ownerToken: _owner,
      ),
    );
    host.onObservation(
      _observation(ForumMessageAttentionState.present),
      context: const ForumMessageAttentionRequestContext(
        viewerUserId: '42',
        requestSequence: 3,
        ownerToken: 'unverified',
      ),
    );
    expect(controller.value.hasAttention, isFalse);
  });

  test(
    'disposed host rejects captured work without touching its controller',
    () {
      final controller = MessageAttentionController();
      final host = MessageAttentionNetworkHost(
        controller: controller,
        readOwner: () => _owner,
      );
      final context = host.captureRequest()!;
      host.dispose();
      controller.dispose();
      expect(host.captureRequest(), isNull);
      expect(
        () => host.onObservation(
          _observation(ForumMessageAttentionState.present),
          context: context,
        ),
        returnsNormally,
      );
    },
  );
}
