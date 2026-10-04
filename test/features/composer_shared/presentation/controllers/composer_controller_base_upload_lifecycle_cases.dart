part of 'composer_controller_base_test.dart';

void _uploadLifecycleCases() {
  test(
    'active upload refresh isolates old uploaded/completed/error from the new run',
    () async {
      const args = _TestArgs(fid: '33', tid: '100');
      final uploads = _UploadRunFixture();
      final container = _buildContainer(
        imagePicker: _FakeImagePicker(images: [_pickedUploadImages.first]),
        imageUploadCoordinator: uploads,
      );
      addTearDown(() async {
        container.dispose();
        await uploads.close();
      });
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      await container.read(_testControllerProvider(args).notifier).pickImages();
      expect(
        container.read(_testControllerProvider(args)).value!.isUploadingImages,
        isTrue,
      );

      await container.refresh(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);
      controller.updateMessage('new session input');
      await controller.pickImages();
      expect(uploads.attachmentsByRun, hasLength(2));
      final beforeOldEvents = controller.latestState!;
      uploads.uploaded(run: 0, slot: 0, aid: 'obsolete');
      uploads.completed(run: 0);
      uploads.eventsByRun[0].addError(StateError('obsolete stream error'));
      await _drain();
      expect(controller.latestState, same(beforeOldEvents));
      expect(controller.latestState?.message, 'new session input');
      expect(controller.latestState?.isUploadingImages, isTrue);
      expect(controller.latestState?.pendingAttachmentAids, isEmpty);

      uploads.uploaded(run: 1, slot: 0, aid: 'fresh');
      uploads.completed(run: 1);
      await _drain();
      expect(controller.latestState?.message, 'new session input');
      expect(controller.latestState?.isUploadingImages, isFalse);
      expect(controller.latestState?.pendingAttachmentAids, ['fresh']);
      expect(controller.latestState?.imageUploadFailure, isNull);
      expect(
        controller.latestState?.imageAttachments
            .where((item) => item.aid != null)
            .map((item) => item.aid),
        ['fresh'],
      );
      await controller.flushDraft();
    },
  );

  test(
    'picker returning after reset cannot restart uploads or restore attachments',
    () async {
      const args = _TestArgs(fid: '33', tid: '100');
      final picker = _DeferredUploadPicker();
      final uploads = _UploadRunFixture();
      final container = _buildContainer(
        imagePicker: picker,
        imageUploadCoordinator: uploads,
      );
      addTearDown(() async {
        container.dispose();
        await uploads.close();
      });
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);
      final picking = controller.pickImages();
      await controller.resetDraft();
      picker.result.complete(_pickedUploadImages);
      await picking;
      await _drain();
      expect(uploads.attachmentsByRun, isEmpty);
      expect(controller.latestState?.imageAttachments, isEmpty);
      expect(controller.latestState?.isUploadingImages, isFalse);
    },
  );

  test('picker returning after disposal cannot touch an expired Ref', () async {
    const args = _TestArgs(fid: '33', tid: '100');
    final picker = _DeferredUploadPicker();
    final uploads = _UploadRunFixture();
    final container = _buildContainer(
      imagePicker: picker,
      imageUploadCoordinator: uploads,
    );
    _keepAlive(container, args);
    await container.read(_testControllerProvider(args).future);
    final controller = container.read(_testControllerProvider(args).notifier);
    final picking = controller.pickImages();
    container.dispose();
    picker.result.complete(_pickedUploadImages);
    await picking;
    expect(uploads.attachmentsByRun, isEmpty);
    expect(controller.latestState?.imageAttachments, isEmpty);
    await uploads.close();
  });

  test('picker from an older build cannot modify refreshed input', () async {
    const args = _TestArgs(fid: '33', tid: '100');
    final picker = _DeferredUploadPicker();
    final uploads = _UploadRunFixture();
    final container = _buildContainer(
      imagePicker: picker,
      imageUploadCoordinator: uploads,
    );
    addTearDown(() async {
      container.dispose();
      await uploads.close();
    });
    _keepAlive(container, args);
    await container.read(_testControllerProvider(args).future);
    final picking = container
        .read(_testControllerProvider(args).notifier)
        .pickImages();
    await container.refresh(_testControllerProvider(args).future);
    final controller = container.read(_testControllerProvider(args).notifier);
    controller.updateMessage('refreshed input');
    picker.result.complete(_pickedUploadImages);
    await picking;
    expect(controller.latestState?.message, 'refreshed input');
    expect(controller.latestState?.imageAttachments, isEmpty);
    expect(uploads.attachmentsByRun, isEmpty);
  });

  test(
    'stream error keeps partial successes pending in picker order and rejects late events',
    () async {
      const args = _TestArgs(fid: '33', tid: '100');
      final uploads = _UploadRunFixture();
      final container = _buildContainer(
        imagePicker: _FakeImagePicker(images: _pickedUploadImages),
        imageUploadCoordinator: uploads,
      );
      addTearDown(() async {
        container.dispose();
        await uploads.close();
      });
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);
      controller.updateMessage('owned input');
      final before = controller.latestState!;
      await controller.pickImages(
        insertionAnchor: ComposerInsertionAnchor(
          baseRevision: before.messageRevision,
          selection: ComposerSelection(
            start: before.message.length,
            end: before.message.length,
          ),
          mode: ComposerEditorMode.source,
        ),
      );
      expect(uploads.attachmentsByRun.single.map((item) => item.fileName), [
        'first.jpg',
        'second.jpg',
        'third.jpg',
      ]);
      uploads.uploaded(run: 0, slot: 2, aid: '30');
      uploads.failed(run: 0, slot: 1);
      uploads.uploaded(run: 0, slot: 0, aid: '10');
      uploads.eventsByRun.single.addError(
        StateError('controlled partial failure'),
      );
      await _drain();
      final settled = controller.latestState!;
      expect(settled.message, 'owned input');
      expect(settled.pendingAttachmentAids, ['10', '30']);
      expect(settled.isUploadingImages, isFalse);
      expect(
        settled.imageUploadFailure?.code,
        ComposerImageUploadFailureCode.unknown,
      );
      uploads.uploaded(run: 0, slot: 1, aid: 'late');
      uploads.completed(run: 0);
      await _drain();
      final late = controller.latestState!;
      expect(late.pendingAttachmentAids, ['10', '30']);
      expect(late.imageAttachments[1].aid, isNull);
      expect(late.isUploadingImages, isFalse);
      expect(late.imageUploadCurrent, settled.imageUploadCurrent);
      await controller.flushDraft();
    },
  );

  test('old completed batch cannot settle a new upload after reset', () async {
    const args = _TestArgs(fid: '33', tid: '100');
    final uploads = _UploadRunFixture();
    final container = _buildContainer(
      imagePicker: _FakeImagePicker(images: [_pickedUploadImages.first]),
      imageUploadCoordinator: uploads,
    );
    addTearDown(() async {
      container.dispose();
      await uploads.close();
    });
    _keepAlive(container, args);
    await container.read(_testControllerProvider(args).future);
    final controller = container.read(_testControllerProvider(args).notifier);
    await controller.pickImages();
    await controller.resetDraft();
    await controller.pickImages();
    uploads.uploaded(run: 0, slot: 0, aid: 'obsolete');
    uploads.completed(run: 0);
    await _drain();
    expect(controller.latestState?.isUploadingImages, isTrue);
    expect(controller.latestState?.pendingAttachmentAids, isEmpty);
    uploads.uploaded(run: 1, slot: 0, aid: 'fresh');
    uploads.completed(run: 1);
    await _drain();
    expect(controller.latestState?.isUploadingImages, isFalse);
    expect(controller.latestState?.pendingAttachmentAids, ['fresh']);
    expect(controller.latestState?.imageAttachments.single.aid, 'fresh');
    await controller.flushDraft();
  });
}

const _pickedUploadImages = [
  ComposerPickedImage(
    path: '/third.jpg',
    fileName: 'third.jpg',
    mimeType: 'image/jpeg',
    originalIndex: 2,
  ),
  ComposerPickedImage(
    path: '/first.jpg',
    fileName: 'first.jpg',
    mimeType: 'image/jpeg',
    originalIndex: 0,
  ),
  ComposerPickedImage(
    path: '/second.jpg',
    fileName: 'second.jpg',
    mimeType: 'image/jpeg',
    originalIndex: 1,
  ),
];

final class _DeferredUploadPicker implements ComposerImagePicker {
  final result = Completer<List<ComposerPickedImage>>();
  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() => result.future;
}

final class _UploadRunFixture implements ComposerImageUploadCoordinator {
  final attachmentsByRun = <List<ComposerImageAttachment>>[];
  final eventsByRun = <StreamController<ComposerImageUploadEvent>>[];

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) {
    attachmentsByRun.add(attachments);
    final events = StreamController<ComposerImageUploadEvent>.broadcast();
    eventsByRun.add(events);
    return events.stream;
  }

  void uploaded({required int run, required int slot, required String aid}) {
    final localId = attachmentsByRun[run][slot].localId;
    eventsByRun[run].add(
      ComposerImageUploadEvent.uploaded(
        localId: localId,
        current: slot + 1,
        total: attachmentsByRun[run].length,
        uploadedImage: ComposerUploadedImage(
          localId: localId,
          aid: aid,
          uploadedAt: DateTime.now(),
        ),
      ),
    );
  }

  void failed({required int run, required int slot}) => eventsByRun[run].add(
    ComposerImageUploadEvent.failed(
      localId: attachmentsByRun[run][slot].localId,
      current: slot + 1,
      total: attachmentsByRun[run].length,
      failure: const ComposerImageUploadFailure(
        code: ComposerImageUploadFailureCode.unknown,
      ),
    ),
  );

  void completed({required int run}) => eventsByRun[run].add(
    ComposerImageUploadEvent.completed(total: attachmentsByRun[run].length),
  );

  @override
  void cancel() {}

  Future<void> close() async {
    for (final events in eventsByRun) {
      await events.close();
    }
  }
}
