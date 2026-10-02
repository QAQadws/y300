import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/presentation/blog/blog_action_controller.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../test_support/blog_operation_fixture.dart';

void main() {
  late BlogOperationFixture service;
  String? actor;
  BlogActionController make({UserBlogAction action = UserBlogAction.delete}) {
    final controller = BlogActionController(
      target: blogActionTarget(action),
      service: service,
      currentActor: () => actor,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    service = BlogOperationFixture();
    actor = '101';
  });

  for (final action in [
    UserBlogAction.delete,
    UserBlogAction.pin,
    UserBlogAction.unpin,
  ]) {
    test(
      '$action prepares without writing and consumes exactly one proof',
      () async {
        final controller = make(action: action);
        final prepare = controller.prepare();
        await controller.prepare();
        await controller.submit();
        expect(service.preparations, hasLength(1));
        expect(service.submissions, isEmpty);
        service.prepared();
        await prepare;
        await controller.prepare();
        expect(service.preparations, hasLength(1));
        final submit = controller.submit();
        expect(await controller.submit(), isNull);
        service.applied();
        expect((await submit)?.target, blogActionTarget(action));
        expect(service.submissions.single.actor, '101');
        await controller.prepare();
        await controller.submit();
        expect(service.preparations, hasLength(1));
        expect(service.submissions, hasLength(1));
      },
    );
  }

  for (final result in <DataCommandResult<UserBlogReceipt>>[
    const DataCommandRejected(blogActionWriteFailure),
    const DataCommandNotSent(blogActionWriteFailure),
    const DataCommandUnsupported(),
  ]) {
    test(
      '${result.runtimeType} requires fresh preparation and confirmation',
      () async {
        final controller = make();
        var prepare = controller.prepare();
        service.prepared();
        await prepare;
        var submit = controller.submit();
        service.submissions.last.result.complete(result);
        expect(await submit, isNull);
        await controller.submit();
        expect(service.submissions, hasLength(1));
        prepare = controller.prepare();
        service.prepared();
        await prepare;
        expect(service.submissions, hasLength(1));
        submit = controller.submit();
        expect(
          service.submissions[1].preparation.token,
          isNot(same(service.submissions[0].preparation.token)),
        );
        service.applied();
        expect(await submit, isNotNull);
      },
    );
  }

  for (final failure in ['unknown', 'throw', 'target', 'id']) {
    test('$failure after submission never permits replay', () async {
      final controller = make();
      final prepare = controller.prepare();
      service.prepared();
      await prepare;
      final submit = controller.submit();
      switch (failure) {
        case 'unknown':
          service.submissions.last.result.complete(
            const DataCommandOutcomeUnknown(blogActionWriteFailure),
          );
        case 'throw':
          service.submissions.last.result.completeError(
            StateError('untrusted transport error'),
          );
        case 'target':
          service.applied(target: blogActionTarget(UserBlogAction.pin));
        case 'id':
          service.applied(blogId: '12');
      }
      expect(await submit, isNull);
      expect(controller.value.phase, BlogActionPhase.unknown);
      await controller.prepare();
      await controller.submit();
      expect(service.submissions, hasLength(1));
      expect(service.preparations, hasLength(1));
    });
  }

  for (final invalid in ['unsupported', 'wrong-target', 'throw']) {
    test('$invalid preparation cannot submit', () async {
      final controller = make();
      final prepare = controller.prepare();
      if (invalid == 'throw') {
        service.preparations.last.result.completeError(
          StateError('fixture read error'),
        );
      } else {
        service.prepared(
          supported: invalid != 'unsupported',
          target: invalid == 'wrong-target'
              ? blogActionTarget(UserBlogAction.pin)
              : null,
        );
      }
      await prepare;
      expect(controller.value.phase, BlogActionPhase.failed);
      await controller.submit();
      expect(service.submissions, isEmpty);
    });
  }

  test('actor loss before submission discards proof', () async {
    final controller = make();
    final prepare = controller.prepare();
    service.prepared();
    await prepare;
    actor = null;
    await controller.submit();
    expect(controller.value.phase, BlogActionPhase.expired);
    actor = '101';
    await controller.prepare();
    await controller.submit();
    expect(service.preparations, hasLength(1));
    expect(service.submissions, isEmpty);
  });

  for (final submitting in [false, true]) {
    test(
      'account change during ${submitting ? 'POST' : 'GET'} stays expired after ABA',
      () async {
        final controller = make();
        final prepare = controller.prepare();
        Future<UserBlogReceipt?>? submit;
        if (submitting) {
          service.prepared();
          await prepare;
          submit = controller.submit();
        }
        actor = '202';
        controller.expire();
        actor = '101';
        expect(
          (submitting
                  ? service.submissions.last.cancellation
                  : service.preparations.last.cancellation)!
              .isCancelled,
          isTrue,
        );
        if (submitting) {
          service.applied();
          expect(await submit, isNull);
        } else {
          service.prepared();
          await prepare;
        }
        expect(controller.value.phase, BlogActionPhase.expired);
        await controller.prepare();
        expect(service.preparations, hasLength(1));
      },
    );

    test(
      'dispose during ${submitting ? 'POST' : 'GET'} cancels and drops late completion',
      () async {
        final controller = BlogActionController(
          target: blogActionTarget(UserBlogAction.delete),
          service: service,
          currentActor: () => actor,
        );
        final prepare = controller.prepare();
        Future<UserBlogReceipt?>? submit;
        if (submitting) {
          service.prepared();
          await prepare;
          submit = controller.submit();
        }
        controller.dispose();
        expect(
          (submitting
                  ? service.submissions.last.cancellation
                  : service.preparations.last.cancellation)!
              .isCancelled,
          isTrue,
        );
        if (submitting) {
          service.applied();
          expect(await submit, isNull);
        } else {
          service.prepared();
          await prepare;
        }
      },
    );
  }
}
