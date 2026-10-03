import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/profile_friend_action_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

import '../test_support/profile_friend_operation_fixture.dart';

void main() {
  late ProfileFriendOperationFixture service;
  VerifiedProfileOwner? owner;

  ProfileFriendActionController make({bool remove = false}) {
    final controller = ProfileFriendActionController(
      owner: (uid: '101', revision: 0),
      targetUserId: '202',
      actionLink: profileFriendLink(remove: remove),
      currentOwner: () => owner,
      prepare: service.prepare,
      submit: service.submit,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    service = ProfileFriendOperationFixture();
    owner = (uid: '101', revision: 0);
  });

  for (final action in ForumFriendAction.values) {
    test('$action prepares without writing and applies exactly once', () async {
      final controller = make(remove: action == ForumFriendAction.remove);
      final prepare = controller.prepare();
      await controller.prepare();
      expect(await controller.submit(), isFalse);
      expect(service.preparations, hasLength(1));
      expect(service.submissions, isEmpty);
      service.prepared(action: action);
      await prepare;
      final submit = controller.submit(note: '你好', groupId: '2');
      expect(await controller.submit(groupId: '2'), isFalse);
      expect(service.submissions, hasLength(1));
      expect(
        service.submissions.single.submission.note,
        action == ForumFriendAction.request ? '你好' : '',
      );
      service.applied();
      expect(await submit, isTrue);
      expect(controller.value.phase, ProfileFriendActionPhase.applied);
      await controller.prepare();
      expect(await controller.submit(groupId: '2'), isFalse);
      expect(service.preparations, hasLength(1));
      expect(service.submissions, hasLength(1));
    });
  }

  test(
    'only an advertised group and supported note length can submit',
    () async {
      final controller = make();
      final prepare = controller.prepare();
      service.prepared(noteMaxLength: 3);
      await prepare;
      expect(await controller.submit(note: '超过限制', groupId: '2'), isFalse);
      expect(await controller.submit(note: '你好', groupId: '999'), isFalse);
      expect(service.submissions, isEmpty);
      expect(controller.value.phase, ProfileFriendActionPhase.ready);
      final submit = controller.submit(note: '你好', groupId: '2');
      service.applied();
      expect(await submit, isTrue);
    },
  );

  for (final invalid in [
    'actor',
    'target',
    'action',
    'capability',
    'provenance',
    'groups',
    'note-limit',
  ]) {
    test('$invalid preparation cannot authorize a command', () async {
      final controller = make();
      final prepare = controller.prepare();
      service.prepared(
        actor: invalid == 'actor' ? '303' : null,
        target: invalid == 'target' ? '303' : null,
        action: invalid == 'action' ? ForumFriendAction.remove : null,
        capabilityAction: invalid == 'capability'
            ? ForumFriendAction.remove
            : null,
        metadata: invalid == 'provenance'
            ? const DataReadMetadata(
                origin: DataReadOrigin.freshSnapshot,
                freshness: DataReadFreshness.freshCache,
              )
            : const DataReadMetadata.network(),
        groups: invalid == 'groups'
            ? const [
                ForumFriendGroup(id: '0', name: 'a'),
                ForumFriendGroup(id: '0', name: 'b'),
              ]
            : null,
        noteMaxLength: invalid == 'note-limit' ? 0 : 30,
      );
      await prepare;
      expect(controller.value.phase, ProfileFriendActionPhase.failed);
      expect(await controller.submit(groupId: '2'), isFalse);
      expect(service.submissions, isEmpty);
    });
  }

  for (final failure in ['unknown', 'throw', 'actor', 'target', 'action']) {
    test('$failure command result cannot refresh or replay', () async {
      final controller = make();
      final prepare = controller.prepare();
      service.prepared();
      await prepare;
      final submit = controller.submit(groupId: '2');
      switch (failure) {
        case 'unknown':
          service.submissions.last.result.complete(
            const DataCommandOutcomeUnknown(profileFriendWriteFailure),
          );
        case 'throw':
          service.submissions.last.result.completeError(
            StateError('untrusted POST error'),
          );
        case 'actor':
          service.applied(actor: '303');
        case 'target':
          service.applied(target: '303');
        case 'action':
          service.applied(action: ForumFriendAction.approve);
      }
      expect(await submit, isFalse);
      expect(controller.value.phase, ProfileFriendActionPhase.unknown);
      await controller.prepare();
      expect(await controller.submit(groupId: '2'), isFalse);
      expect(service.preparations, hasLength(1));
      expect(service.submissions, hasLength(1));
    });
  }

  for (final result in <DataCommandResult<ForumFriendReceipt>>[
    const DataCommandRejected(profileFriendWriteFailure),
    const DataCommandNotSent(profileFriendWriteFailure),
    const DataCommandUnsupported(),
  ]) {
    test('${result.runtimeType} needs a fresh GET and confirmation', () async {
      final controller = make();
      var prepare = controller.prepare();
      service.prepared();
      await prepare;
      var submit = controller.submit(groupId: '2');
      service.submissions.last.result.complete(result);
      expect(await submit, isFalse);
      expect(await controller.submit(groupId: '2'), isFalse);
      prepare = controller.prepare();
      service.prepared();
      await prepare;
      expect(service.submissions, hasLength(1));
      submit = controller.submit(groupId: '2');
      expect(
        service.submissions.last.submission.preparation.token,
        isNot(same(service.submissions.first.submission.preparation.token)),
      );
      service.applied();
      expect(await submit, isTrue);
    });
  }

  for (final submitting in [false, true]) {
    test(
      'same UID new session drops late ${submitting ? 'POST' : 'GET'}',
      () async {
        final controller = make();
        final prepare = controller.prepare();
        Future<bool>? submit;
        if (submitting) {
          service.prepared();
          await prepare;
          submit = controller.submit(groupId: '2');
        }
        owner = (uid: '101', revision: 1);
        controller.expire();
        expect(
          submitting
              ? service.submissions.last.submission.cancellation?.isCancelled
              : service.preparations.last.query.cancellation?.isCancelled,
          isTrue,
        );
        if (submitting) {
          service.applied();
          expect(await submit, isFalse);
        } else {
          service.prepared();
          await prepare;
        }
        expect(controller.value.phase, ProfileFriendActionPhase.expired);
        await controller.prepare();
        expect(service.preparations, hasLength(1));
      },
    );
  }

  test('owner change before submit discards the prepared proof', () async {
    final controller = make();
    final prepare = controller.prepare();
    service.prepared();
    await prepare;
    owner = null;
    expect(await controller.submit(groupId: '2'), isFalse);
    expect(controller.value.phase, ProfileFriendActionPhase.expired);
    expect(service.submissions, isEmpty);
  });

  test('disposing a prepared route cancels its pending command', () async {
    final controller = ProfileFriendActionController(
      owner: (uid: '101', revision: 0),
      targetUserId: '202',
      actionLink: profileFriendLink(),
      currentOwner: () => owner,
      prepare: service.prepare,
      submit: service.submit,
    );
    final prepare = controller.prepare();
    service.prepared();
    await prepare;
    final submit = controller.submit(groupId: '2');
    controller.dispose();
    expect(
      service.submissions.last.submission.cancellation?.isCancelled,
      isTrue,
    );
    service.applied();
    expect(await submit, isFalse);
  });
}
