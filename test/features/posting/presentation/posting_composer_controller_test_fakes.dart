part of 'posting_composer_controller_test.dart';

PostingComposerArgs _args({String fid = '33'}) {
  return PostingComposerArgs(target: PostingTarget(fid: fid));
}

final class _TestThreadCreationToken implements ThreadCreationPreparationToken {
  const _TestThreadCreationToken();
}

final ThreadCreationCapabilities _threadCreationCapabilities =
    ThreadCreationCapabilities(
      values: DataCapabilitySet<ThreadCreationCapability>.supported(
        ThreadCreationCapability.values,
      ),
    );

ThreadCreationPreparation _metadataWithTypes({required bool typeRequired}) {
  return ThreadCreationPreparation(
    fid: '33',
    forumName: '版块名',
    threadTypes: const [
      ThreadCreationType(id: '111', name: '日常'),
      ThreadCreationType(id: '222', name: '汉化'),
    ],
    threadSorts: const <ThreadCreationSort>[],
    typeRequired: typeRequired,
    sortRequired: false,
    maxSubjectLength: 0,
    maxMessageLength: 0,
    token: const _TestThreadCreationToken(),
  );
}

ThreadCreationPreparation _metadataNoTypes() {
  return const ThreadCreationPreparation(
    fid: '33',
    forumName: '版块名',
    threadTypes: <ThreadCreationType>[],
    threadSorts: <ThreadCreationSort>[],
    typeRequired: false,
    sortRequired: false,
    maxSubjectLength: 0,
    maxMessageLength: 0,
    token: _TestThreadCreationToken(),
  );
}

ThreadCreationPreparation _metadataWithLengthLimits({
  int maxSubjectLength = 0,
  int maxMessageLength = 0,
}) {
  return ThreadCreationPreparation(
    fid: '33',
    forumName: '版块名',
    threadTypes: const <ThreadCreationType>[],
    threadSorts: const <ThreadCreationSort>[],
    typeRequired: false,
    sortRequired: false,
    maxSubjectLength: maxSubjectLength,
    maxMessageLength: maxMessageLength,
    token: const _TestThreadCreationToken(),
  );
}

ProviderContainer _buildContainer({
  ComposerDraftRepository? draftRepository,
  ThreadCreationPreparationRepository? metadataRepository,
  ThreadCreationCommand? threadCreationCommand,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
}) {
  return ProviderContainer(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        _MemoryComposerPreferencesRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(
        imagePicker ?? _FakeImagePicker(),
      ),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        imageUploadCoordinator ?? _FakeUploadCoordinator(),
      ),
      threadCreationPreparationProvider.overrideWithValue(
        metadataRepository ??
            _FakeMetadataRepository.success(_metadataNoTypes()),
      ),
      threadCreationCommandProvider.overrideWithValue(
        threadCreationCommand ?? _FakeThreadCreationCommand(),
      ),
    ],
  );
}

class _MemoryComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  ComposerPreferences preferences = ComposerPreferences.defaults();

  @override
  Future<ComposerPreferences> load() async => preferences;

  @override
  Future<void> save(ComposerPreferences preferences) async {
    this.preferences = preferences;
  }
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
        .where(
          (draft) => draft.identity.fid == fid && draft.identity.tid == tid,
        )
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
    return ComposerDraftPruneResult(removedCount: 0, keptCount: _drafts.length);
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

class _FakeMetadataRepository implements ThreadCreationPreparationRepository {
  _FakeMetadataRepository._(this._queue);

  factory _FakeMetadataRepository.success(ThreadCreationPreparation metadata) {
    return _FakeMetadataRepository._([
      DataReadSuccess<ThreadCreationPreparation, ThreadCreationCapabilities>(
        data: metadata,
        capabilities: _threadCreationCapabilities,
        metadata: const DataReadMetadata.network(),
      ),
    ]);
  }

  factory _FakeMetadataRepository.failure(
    DataReadFailure<ThreadCreationPreparation, ThreadCreationCapabilities>
    failure,
  ) {
    return _FakeMetadataRepository._([failure]);
  }

  /// 还未消费的下一批响应；空了就 sticky 在 [_last]，方便后续无须显式排队。
  final List<
    DataReadResult<ThreadCreationPreparation, ThreadCreationCapabilities>
  >
  _queue;
  DataReadResult<ThreadCreationPreparation, ThreadCreationCapabilities>? _last;
  int callCount = 0;

  @override
  ThreadCreationCapabilities get capabilities => _threadCreationCapabilities;

  void queueSuccess(ThreadCreationPreparation metadata) {
    _queue.add(
      DataReadSuccess<ThreadCreationPreparation, ThreadCreationCapabilities>(
        data: metadata,
        capabilities: _threadCreationCapabilities,
        metadata: const DataReadMetadata.network(),
      ),
    );
  }

  @override
  Future<DataReadResult<ThreadCreationPreparation, ThreadCreationCapabilities>>
  load(ThreadCreationPreparationRequest request) async {
    callCount += 1;
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _last = next;
      return next;
    }
    return _last!;
  }
}

class _FakeThreadCreationCommand implements ThreadCreationCommand {
  _FakeThreadCreationCommand({
    DataCommandResult<ThreadCreationReceipt>? result,
    Future<DataCommandResult<ThreadCreationReceipt>>? asyncResult,
  }) : _result =
           result ??
           const DataCommandApplied<ThreadCreationReceipt>(
             ThreadCreationReceipt(
               tid: '900001',
               pid: '910001',
               publicationState: ThreadPublicationState.published,
               readAccess: ThreadReadAccessEvidence(
                 kind: ThreadReadAccessEvidenceKind.unrestricted,
                 requested: 0,
                 actual: 0,
               ),
             ),
           ),
       _asyncResult = asyncResult;

  final DataCommandResult<ThreadCreationReceipt> _result;
  final Future<DataCommandResult<ThreadCreationReceipt>>? _asyncResult;
  final List<ThreadCreationSubmission> submissions =
      <ThreadCreationSubmission>[];

  @override
  ThreadCreationCapabilities get capabilities => _threadCreationCapabilities;

  @override
  Future<DataCommandResult<ThreadCreationReceipt>> execute(
    ThreadCreationSubmission submission,
  ) async {
    submissions.add(submission);
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
        ComposerImageUploadEventType.failed => ComposerImageUploadEvent.failed(
          localId: localId,
          current: event.current,
          total: event.total,
          failure:
              event.failure ??
              const ComposerImageUploadFailure(
                code: ComposerImageUploadFailureCode.unknown,
              ),
        ),
        ComposerImageUploadEventType.completed =>
          ComposerImageUploadEvent.completed(total: event.total),
      };
    }
  }
}
