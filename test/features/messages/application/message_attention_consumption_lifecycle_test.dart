import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/application/message_attention_consumption_lifecycle.dart';
import 'package:y300/features/messages/application/message_attention_controller.dart';

const _owner = (sessionOwner: (uid: '42', revision: 1), sourceGeneration: 3);
const _absent = ForumMessageAttentionState.absent;
const _present = ForumMessageAttentionState.present;
const _unknown = ForumMessageAttentionState.unknown;

ForumMessageAttentionObservation _categories({
  ForumMessageAttentionState messages = _unknown,
  ForumMessageAttentionState notifications = _unknown,
}) => ForumMessageAttentionObservation(
  viewerUserId: '42',
  source: ForumMessageAttentionSource.api,
  privateMessages: messages,
  notifications: notifications,
);

ForumMessageAttentionObservation _aggregate(ForumMessageAttentionState hint) =>
    ForumMessageAttentionObservation(
      viewerUserId: '42',
      source: ForumMessageAttentionSource.mobileHtml,
      combinedHint: hint,
    );

void main() {
  late MessageAttentionController controller;
  late MessageAttentionOwner? currentOwner;
  late MessageAttentionConsumptionLifecycle lifecycle;
  late List<(MessageAttentionOwner, int)> calibrations;
  late List<MessageAttentionFreshSample> samples;

  void accept(ForumMessageAttentionObservation observation, [int? sequence]) {
    controller.accept(
      observation,
      owner: _owner,
      sequence: sequence ?? controller.nextRequestSequence(),
    );
  }

  void consume(MessageAttentionConsumptionKind kind) =>
      lifecycle.onReadSucceeded(owner: _owner, kind: kind);

  setUp(() {
    controller = MessageAttentionController()..setOwner(_owner);
    currentOwner = _owner;
    calibrations = [];
    samples = [];
    final subscription = controller.freshSamples.listen(samples.add);
    addTearDown(subscription.cancel);
    lifecycle = MessageAttentionConsumptionLifecycle(
      controller: controller,
      readOwner: () => currentOwner,
      requestCalibration: (owner, minimumSequence) =>
          calibrations.add((owner, minimumSequence)),
    );
  });
  tearDown(() => controller.dispose());

  test(
    'consumption preserves dots and local acknowledgement until calibration',
    () {
      accept(_aggregate(_present));
      controller.acknowledgeMore();
      final before = controller.value;
      expect(lifecycle.captureOwner(), _owner);
      consume(MessageAttentionConsumptionKind.privateMessages);
      expect(controller.value, before);
      expect(calibrations.single, (_owner, 1));
      accept(_categories(messages: _absent, notifications: _present));
      expect(controller.value.hasAttention, isTrue);
      expect(controller.value.attentionEpoch, 1);
      expect(controller.value.acknowledgedMoreEpoch, 1);
    },
  );

  test(
    'success barrier includes requests started during the consuming read',
    () {
      accept(_categories(messages: _absent, notifications: _absent));
      final captured = lifecycle.captureOwner()!;
      final beforeRead = controller.nextRequestSequence();
      final duringRead = controller.nextRequestSequence();
      lifecycle.onReadSucceeded(
        owner: captured,
        kind: MessageAttentionConsumptionKind.privateMessages,
      );
      expect(calibrations.single.$2, duringRead);
      accept(_categories(messages: _present), beforeRead);
      accept(_categories(messages: _present), duringRead);
      expect(controller.value.privateMessages, _absent);
      expect(controller.value.hasAttention, isFalse);
      accept(_categories(messages: _present));
      expect(controller.value.privateMessages, _present);
    },
  );

  test(
    'private barrier leaves later evidence for the other category usable',
    () {
      accept(_categories(messages: _absent, notifications: _absent));
      final pending = controller.nextRequestSequence();
      consume(MessageAttentionConsumptionKind.privateMessages);
      accept(_categories(messages: _present, notifications: _present), pending);
      expect(controller.value.privateMessages, _absent);
      expect(controller.value.notifications, _present);
      expect(samples, hasLength(1));
    },
  );

  test(
    'notification barrier leaves private evidence usable but blocks aggregates',
    () {
      accept(_categories(messages: _absent, notifications: _absent));
      final pending = controller.nextRequestSequence();
      consume(MessageAttentionConsumptionKind.notifications);
      accept(_categories(messages: _present, notifications: _present), pending);
      expect(controller.value.notifications, _absent);
      expect(controller.value.privateMessages, _present);
      accept(_aggregate(_absent), pending);
      expect(controller.value.hasAttention, isTrue);
      accept(_aggregate(_absent));
      expect(controller.value.hasAttention, isFalse);
    },
  );

  test(
    'pre-consumption category negatives cannot retire a historical aggregate',
    () {
      accept(_aggregate(_present));
      accept(_categories(messages: _absent));
      consume(MessageAttentionConsumptionKind.privateMessages);
      accept(_categories(notifications: _absent));
      expect(controller.value.hasAttention, isTrue);
      accept(_categories(messages: _absent));
      expect(controller.value.hasAttention, isFalse);
    },
  );

  test(
    'fresh complete samples publish even when the UI value is unchanged',
    () {
      var uiChanges = 0;
      controller.addListener(() => uiChanges++);
      accept(_aggregate(_present));
      accept(_aggregate(_present));
      expect(uiChanges, 1);
      expect(samples.map((sample) => sample.sequence), [1, 2]);
      final before = controller.latestCompleteSequence;
      accept(_categories(messages: _present));
      accept(_categories());
      expect(controller.latestCompleteSequence, before);
      expect(samples, hasLength(2));
    },
  );

  test('stale complete responses do not reset freshness after a barrier', () {
    accept(_aggregate(_present));
    final pending = controller.nextRequestSequence();
    consume(MessageAttentionConsumptionKind.privateMessages);
    accept(_aggregate(_absent), pending);
    accept(_categories(messages: _absent, notifications: _absent), pending);
    expect(controller.latestCompleteSequence, 1);
    accept(_categories(messages: _absent, notifications: _absent));
    expect(controller.latestCompleteSequence, 3);
    expect(controller.value.hasAttention, isFalse);
  });

  test(
    'unverified and mismatched owners never capture a consumption token',
    () {
      currentOwner = null;
      expect(lifecycle.captureOwner(), isNull);
      consume(MessageAttentionConsumptionKind.privateMessages);
      currentOwner = (
        sessionOwner: (uid: '42', revision: 2),
        sourceGeneration: 3,
      );
      expect(lifecycle.captureOwner(), isNull);
      consume(MessageAttentionConsumptionKind.privateMessages);
      expect(calibrations, isEmpty);
    },
  );

  test(
    'source/session changes and disposed controllers reject old completions',
    () {
      final old = lifecycle.captureOwner()!;
      currentOwner = (sessionOwner: _owner.sessionOwner, sourceGeneration: 4);
      controller.setOwner(currentOwner);
      lifecycle.onReadSucceeded(
        owner: old,
        kind: MessageAttentionConsumptionKind.notifications,
      );
      expect(calibrations, isEmpty);
      controller.setOwner(_owner);
      currentOwner = _owner;
      controller.dispose();
      consume(MessageAttentionConsumptionKind.privateMessages);
      expect(calibrations, isEmpty);
      // Replace it so the fixture still has exactly one disposal per instance.
      controller = MessageAttentionController();
    },
  );
}
