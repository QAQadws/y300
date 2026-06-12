part of 'posting_composer_controller_test.dart';

PostingComposerArgs _args({String fid = '33'}) {
  return PostingComposerArgs(target: PostingTarget(fid: fid));
}

NewThreadFormMetadata _metadataWithTypes({required bool typeRequired}) {
  return NewThreadFormMetadata(
    fid: '33',
    forumName: '版块名',
    formHash: 'fh',
    threadTypes: const [
      ThreadType(id: '111', name: '日常'),
      ThreadType(id: '222', name: '汉化'),
    ],
    threadSorts: const <ThreadSort>[],
    typeRequired: typeRequired,
    sortRequired: false,
  );
}

NewThreadFormMetadata _metadataNoTypes() {
  return const NewThreadFormMetadata(
    fid: '33',
    forumName: '版块名',
    formHash: 'fh',
    threadTypes: <ThreadType>[],
    threadSorts: <ThreadSort>[],
    typeRequired: false,
    sortRequired: false,
  );
}

NewThreadFormMetadata _metadataWithLengthLimits({
  int maxSubjectLength = 0,
  int maxMessageLength = 0,
}) {
  return NewThreadFormMetadata(
    fid: '33',
    forumName: '版块名',
    formHash: 'fh',
    threadTypes: const <ThreadType>[],
    threadSorts: const <ThreadSort>[],
    typeRequired: false,
    sortRequired: false,
    maxSubjectLength: maxSubjectLength,
    maxMessageLength: maxMessageLength,
  );
}

ProviderContainer _buildContainer({
  ComposerDraftRepository? draftRepository,
  PostingFormMetadataRepository? metadataRepository,
  NewThreadRepository? newThreadRepository,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
}) {
  return ProviderContainer(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryDraftRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(
        imagePicker ?? _FakeImagePicker(),
      ),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        imageUploadCoordinator ?? _FakeUploadCoordinator(),
      ),
      composerUploadNotificationServiceProvider.overrideWithValue(
        _NoopUploadNotificationService(),
      ),
      postingFormMetadataRepositoryProvider.overrideWithValue(
        metadataRepository ?? _FakeMetadataRepository.success(_metadataNoTypes()),
      ),
      newThreadRepositoryProvider.overrideWithValue(
        newThreadRepository ?? _FakeNewThreadRepository(),
      ),
    ],
  );
}

ProviderSubscription<AsyncValue<PostingComposerState>> _keepAlive(
  ProviderContainer container,
  PostingComposerArgs args,
) {
  return container.listen<AsyncValue<PostingComposerState>>(
    postingComposerControllerProvider(args),
    (_, _) {},
  );
}

Future<void> _drain({int rounds = 4}) async {
  for (var i = 0; i < rounds; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _MemoryDraftRepository implements ComposerDraftRepository {
  final Map<String, ComposerDraftSnapshot> _drafts =
      <String, ComposerDraftSnapshot>{};

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    _drafts.remove(identity.storageKey);
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    return _drafts.values
        .where((draft) => draft.identity.fid == fid && draft.identity.tid == tid)
        .toList(growable: false);
  }

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    return _drafts[identity.storageKey];
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    return ComposerDraftPruneResult(
      removedCount: 0,
      keptCount: _drafts.length,
    );
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    if (draft.isEmpty) {
      _drafts.remove(draft.identity.storageKey);
      return;
    }
    _drafts[draft.identity.storageKey] = draft;
  }
}

class _FakeMetadataRepository implements PostingFormMetadataRepository {
  _FakeMetadataRepository._(this._queue);

  factory _FakeMetadataRepository.success(NewThreadFormMetadata metadata) {
    return _FakeMetadataRepository._([
      ApiSuccess<NewThreadFormMetadata>(metadata),
    ]);
  }

  factory _FakeMetadataRepository.failure(ApiError error) {
    return _FakeMetadataRepository._([
      ApiFailure<NewThreadFormMetadata>(error),
    ]);
  }

  /// 还未消费的下一批响应；空了就 sticky 在 [_last]，方便后续无须显式排队。
  final List<ApiResult<NewThreadFormMetadata>> _queue;
  ApiResult<NewThreadFormMetadata>? _last;
  int callCount = 0;

  void queueSuccess(NewThreadFormMetadata metadata) {
    _queue.add(ApiSuccess<NewThreadFormMetadata>(metadata));
  }

  @override
  Future<ApiResult<NewThreadFormMetadata>> getFormMetadata({
    required String fid,
  }) async {
    callCount += 1;
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _last = next;
      return next;
    }
    return _last!;
  }
}

class _FakeNewThreadRepository implements NewThreadRepository {
  _FakeNewThreadRepository({
    ApiResult<NewThreadSubmissionResult>? result,
    Future<ApiResult<NewThreadSubmissionResult>>? asyncResult,
  })  : _result = result ??
            const ApiSuccess<NewThreadSubmissionResult>(
              NewThreadSubmissionResult(
                tid: '900001',
                pid: '910001',
                message: '发布成功',
              ),
            ),
        _asyncResult = asyncResult;

  final ApiResult<NewThreadSubmissionResult> _result;
  final Future<ApiResult<NewThreadSubmissionResult>>? _asyncResult;
  final List<NewThreadDraftPayload> submittedPayloads = <NewThreadDraftPayload>[];

  @override
  Future<ApiResult<NewThreadSubmissionResult>> submit({
    required NewThreadDraftPayload payload,
  }) async {
    submittedPayloads.add(payload);
    final pending = _asyncResult;
    if (pending != null) {
      return pending;
    }
    return _result;
  }
}

class _FakeImagePicker implements ComposerImagePicker {
  _FakeImagePicker({this.images = const <ComposerPickedImage>[]});

  final List<ComposerPickedImage> images;
  int pickCallCount = 0;

  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async {
    pickCallCount += 1;
    return images;
  }
}

class _FakeUploadCoordinator implements ComposerImageUploadCoordinator {
  _FakeUploadCoordinator({this.events = const <ComposerImageUploadEvent>[]});

  final List<ComposerImageUploadEvent> events;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) async* {
    for (final event in events) {
      if (cancelled) return;
      if (event.type == ComposerImageUploadEventType.completed) {
        yield ComposerImageUploadEvent.completed(total: event.total);
        continue;
      }
      final localId = event.localId.isNotEmpty
          ? event.localId
          : attachments[(event.current - 1)
                  .clamp(0, attachments.length - 1)
                  .toInt()]
              .localId;
      yield switch (event.type) {
        ComposerImageUploadEventType.started =>
          ComposerImageUploadEvent.started(
            localId: localId,
            current: event.current,
            total: event.total,
          ),
        ComposerImageUploadEventType.progress =>
          ComposerImageUploadEvent.progress(
            localId: localId,
            current: event.current,
            total: event.total,
            progress: event.progress ?? 0,
          ),
        ComposerImageUploadEventType.uploaded =>
          ComposerImageUploadEvent.uploaded(
            localId: localId,
            current: event.current,
            total: event.total,
            uploadedImage: ComposerUploadedImage(
              localId: localId,
              aid: event.uploadedImage!.aid,
              uploadedAt: event.uploadedImage!.uploadedAt,
            ),
          ),
        ComposerImageUploadEventType.failed =>
          ComposerImageUploadEvent.failed(
            localId: localId,
            current: event.current,
            total: event.total,
            errorMessage: event.errorMessage ?? '上传失败',
          ),
        ComposerImageUploadEventType.completed =>
          ComposerImageUploadEvent.completed(total: event.total),
      };
    }
  }
}

class _NoopUploadNotificationService
    implements ComposerUploadNotificationService {
  @override
  Future<void> clear() async {}

  @override
  Future<void> showFailure({
    required int failedCount,
    required int total,
  }) async {}

  @override
  Future<void> showProgress({
    required int current,
    required int total,
  }) async {}
}
