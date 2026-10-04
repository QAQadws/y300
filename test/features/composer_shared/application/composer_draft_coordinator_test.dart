import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/application/composer_draft_coordinator.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_draft_repository.dart';

const _identity = ComposerDraftIdentity.thread(fid: '33', tid: '100');

void main() {
  test(
    'close waits for in-flight discard failure and its one cleanup retry',
    () async {
      final repository = _ControlledRepository();
      final drafts = _coordinator(repository, () => 'sent input');
      await drafts.flush();
      final deletion = Completer<void>();
      repository.beforeDelete = deletion.future;
      repository.failNextDelete = true;
      final discarding = drafts.discard();
      await _drain();
      final closing = drafts.close();
      deletion.complete();
      await closing;
      expect(await discarding, isFalse);
      expect(repository.operations, ['save:sent input', 'delete', 'delete']);
      expect(repository.value, isNull);
    },
  );
  test(
    'transient discard failure retries deletion on close without saving sent input',
    () async {
      final repository = _ControlledRepository();
      final drafts = _coordinator(repository, () => 'sent input');
      await drafts.flush();
      repository.failNextDelete = true;
      expect(await drafts.discard(), isFalse);
      expect(repository.value?.message, 'sent input');
      await drafts.close();
      await drafts.close();
      expect(repository.operations, ['save:sent input', 'delete', 'delete']);
      expect(repository.value, isNull);
    },
  );

  test(
    'an applied discard after route close gets one local cleanup retry',
    () async {
      final repository = _ControlledRepository();
      final drafts = _coordinator(repository, () => 'sent input');
      await drafts.close();
      repository.failNextDelete = true;
      expect(await drafts.discard(), isFalse);
      await drafts.close();
      expect(repository.operations, ['save:sent input', 'delete', 'delete']);
      expect(repository.value, isNull);
    },
  );

  test(
    'late delete failure cannot delete new input captured on close',
    () async {
      final repository = _ControlledRepository();
      var input = 'old input';
      final drafts = _coordinator(repository, () => input);
      await drafts.flush();
      final deletion = Completer<void>();
      repository.beforeDelete = deletion.future;
      repository.failNextDelete = true;
      final discarding = drafts.discard();
      await _drain();
      input = 'new input';
      drafts.scheduleSave();
      final closing = drafts.close();
      deletion.complete();
      expect(await discarding, isFalse);
      await closing;
      expect(repository.operations, [
        'save:old input',
        'delete',
        'save:new input',
      ]);
      expect(repository.value?.message, 'new input');
    },
  );
  test('debounce restarts and captures the latest input at 700 ms', () {
    fakeAsync((time) {
      final repository = _ControlledRepository();
      var input = 'first';
      final drafts = _coordinator(repository, () => input);
      drafts.scheduleSave();
      time.elapse(const Duration(milliseconds: 600));
      time.flushMicrotasks();
      expect(repository.operations, isEmpty);
      input = 'last';
      drafts.scheduleSave();
      time.elapse(const Duration(milliseconds: 699));
      time.flushMicrotasks();
      expect(repository.operations, isEmpty);
      time.elapse(const Duration(milliseconds: 1));
      time.flushMicrotasks();
      expect(repository.operations, ['save:last']);
    });
  });

  test('explicit flush cancels pending debounce without a later duplicate', () {
    fakeAsync((time) {
      final repository = _ControlledRepository();
      final drafts = _coordinator(repository, () => 'flushed');
      drafts.scheduleSave();
      unawaited(drafts.flush());
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 2));
      time.flushMicrotasks();
      expect(repository.operations, ['save:flushed']);
    });
  });

  test(
    'writes stay serial and a failed write does not poison the next one',
    () async {
      final repository = _ControlledRepository();
      final gate = Completer<void>();
      repository.beforeSave = gate.future;
      var input = 'first';
      final drafts = _coordinator(repository, () => input);
      final first = drafts.flush();
      await _drain();
      input = 'second';
      final second = drafts.flush();
      await _drain();
      expect(repository.operations, ['save:first']);
      repository.failNextSave = true;
      gate.complete();
      await Future.wait([first, second]);
      expect(repository.operations, ['save:first', 'save:second']);
      expect(repository.value?.message, 'second');
    },
  );

  test(
    'discard follows in-flight save and invalidates queued older snapshots',
    () async {
      final repository = _ControlledRepository();
      final gate = Completer<void>();
      repository.beforeSave = gate.future;
      var input = 'running';
      final drafts = _coordinator(repository, () => input);
      final first = drafts.flush();
      await _drain();
      input = 'queued';
      final second = drafts.flush();
      final deletion = drafts.discard();
      final closing = drafts.close();
      gate.complete();
      await Future.wait([first, second, closing]);
      expect(await deletion, isTrue);
      expect(repository.operations, ['save:running', 'delete']);
      expect(repository.value, isNull);
    },
  );

  test(
    'discard blocks stale saves while a new explicit edit can create a draft',
    () async {
      final repository = _ControlledRepository();
      var input = 'old';
      final drafts = _coordinator(repository, () => input);
      await drafts.flush();
      expect(await drafts.discard(), isTrue);
      await drafts.saveState('late old completion');
      await drafts.flush();
      expect(repository.value, isNull);
      input = 'new edit';
      drafts.scheduleSave();
      await drafts.flush();
      expect(repository.value?.message, 'new edit');
    },
  );

  test(
    'close persists the last input once and rejects all later saves',
    () async {
      final repository = _ControlledRepository();
      var input = 'last input';
      final drafts = _coordinator(repository, () => input);
      drafts.scheduleSave();
      final closing = drafts.close();
      input = 'late callback';
      drafts.scheduleSave();
      await drafts.flush();
      await drafts.saveState(input);
      await closing;
      await drafts.close();
      expect(repository.operations, ['save:last input']);
      expect(repository.value?.message, 'last input');
    },
  );

  test(
    'an applied submission can delete after close without resurrecting input',
    () async {
      final repository = _ControlledRepository();
      final gate = Completer<void>();
      repository.beforeSave = gate.future;
      final drafts = _coordinator(repository, () => 'sent');
      final closing = drafts.close();
      await _drain();
      final applied = drafts.discard();
      gate.complete();
      await closing;
      expect(await applied, isTrue);
      await drafts.saveState('late');
      expect(repository.operations, ['save:sent', 'delete']);
      expect(repository.value, isNull);
    },
  );

  test(
    'restoration arriving after close is ignored and never saved back',
    () async {
      final repository = _ControlledRepository()..value = _snapshot('stored');
      final gate = Completer<void>();
      repository.beforeLoad = gate.future;
      final drafts = _coordinator(repository, () => null);
      final loading = drafts.restore();
      await _drain();
      await drafts.close();
      gate.complete();
      expect(await loading, isNull);
      await drafts.saveRestoredSnapshot(_snapshot('late verification'));
      expect(repository.value?.message, 'stored');
      expect(repository.operations, isEmpty);
    },
  );

  test(
    'queued final snapshots copy the mutable extras and attachment collections',
    () async {
      final repository = _ControlledRepository();
      final gate = Completer<void>();
      repository.beforeSave = gate.future;
      final extras = <String, String>{'type': 'old'};
      final images = <ComposerImageAttachment>[];
      final drafts = ComposerDraftCoordinator<String>(
        repository: repository,
        identity: _identity,
        readState: () => 'captured',
        shouldPersist: (_) => true,
        snapshotFor: (input) =>
            _snapshot(input, extras: extras, images: images),
      );
      final closing = drafts.close();
      extras['type'] = 'new';
      images.add(
        const ComposerImageAttachment(
          localId: 'late',
          localPath: '/late.jpg',
          fileName: 'late.jpg',
          mimeType: 'image/jpeg',
          order: 0,
          status: ComposerImageAttachmentStatus.local,
        ),
      );
      gate.complete();
      await closing;
      expect(repository.value?.extras, {'type': 'old'});
      expect(repository.value?.imageAttachments, isEmpty);
    },
  );
}

ComposerDraftCoordinator<String> _coordinator(
  _ControlledRepository repository,
  String? Function() readState,
) => ComposerDraftCoordinator<String>(
  repository: repository,
  identity: _identity,
  readState: readState,
  shouldPersist: (input) => input.trim().isNotEmpty,
  snapshotFor: (input) => _snapshot(input),
);

ComposerDraftSnapshot _snapshot(
  String message, {
  Map<String, String> extras = const {},
  List<ComposerImageAttachment> images = const [],
}) => ComposerDraftSnapshot(
  identity: _identity,
  message: message,
  useSignature: true,
  updatedAt: DateTime.utc(2026, 10, 4),
  extras: extras,
  imageAttachments: images,
);

Future<void> _drain() => Future<void>.delayed(Duration.zero);

final class _ControlledRepository implements ComposerDraftRepository {
  final operations = <String>[];
  ComposerDraftSnapshot? value;
  Future<void>? beforeSave;
  Future<void>? beforeLoad;
  Future<void>? beforeDelete;
  bool failNextSave = false;
  bool failNextDelete = false;

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    operations.add('save:${draft.message}');
    await beforeSave;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('controlled save failure');
    }
    value = draft;
  }

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    operations.add('delete');
    await beforeDelete;
    if (failNextDelete) {
      failNextDelete = false;
      throw StateError('controlled delete failure');
    }
    value = null;
  }

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    await beforeLoad;
    return value;
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async => ComposerDraftPruneResult(
    removedCount: 0,
    keptCount: value == null ? 0 : 1,
  );

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async => value == null ? [] : [value!];
}
