part of 'composer_controller_base_test.dart';

class _TestArgs {
  const _TestArgs({required this.fid, required this.tid});
  final String fid;
  final String tid;

  ComposerDraftIdentity get identity =>
      ComposerDraftIdentity.thread(fid: fid, tid: tid);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _TestArgs && other.fid == fid && other.tid == tid;
  }

  @override
  int get hashCode => Object.hash(fid, tid);
}

class _TestComposerState extends ComposerStateBase {
  const _TestComposerState({
    required super.message,
    required super.useSignature,
    required super.isSubmitting,
    required super.restoredDraft,
    required super.imageAttachments,
    required super.isUploadingImages,
    required super.imageUploadCurrent,
    required super.imageUploadTotal,
    super.messageRevision,
    super.lastMessageMutation,
    super.pendingAttachmentAids,
    super.pendingAttachmentNotice,
    super.failure,
    super.imageUploadFailure,
    super.draftAttachmentVerification,
  });

  factory _TestComposerState.initial({
    String message = '',
    bool useSignature = true,
    bool restoredDraft = false,
    List<ComposerImageAttachment> imageAttachments = const [],
  }) {
    return _TestComposerState(
      message: message,
      useSignature: useSignature,
      isSubmitting: false,
      restoredDraft: restoredDraft,
      imageAttachments: imageAttachments,
      isUploadingImages: false,
      imageUploadCurrent: 0,
      imageUploadTotal: 0,
    );
  }

  _TestComposerState copyFromPatch(ComposerStatePatch patch) {
    return _TestComposerState(
      message: patch.message ?? message,
      useSignature: patch.useSignature ?? useSignature,
      isSubmitting: patch.isSubmitting ?? isSubmitting,
      restoredDraft: patch.restoredDraft ?? restoredDraft,
      imageAttachments: patch.imageAttachments ?? imageAttachments,
      isUploadingImages: patch.isUploadingImages ?? isUploadingImages,
      imageUploadCurrent: patch.imageUploadCurrent ?? imageUploadCurrent,
      imageUploadTotal: patch.imageUploadTotal ?? imageUploadTotal,
      messageRevision: patch.messageRevision ?? messageRevision,
      lastMessageMutation: patch.clearLastMessageMutation
          ? null
          : patch.lastMessageMutation ?? lastMessageMutation,
      pendingAttachmentAids:
          patch.pendingAttachmentAids ?? pendingAttachmentAids,
      pendingAttachmentNotice: patch.clearPendingAttachmentNotice
          ? null
          : patch.pendingAttachmentNotice ?? pendingAttachmentNotice,
      failure: patch.clearFailure ? null : patch.failure ?? failure,
      imageUploadFailure: patch.clearImageUploadFailure
          ? null
          : patch.imageUploadFailure ?? imageUploadFailure,
      draftAttachmentVerification:
          patch.draftAttachmentVerification ?? draftAttachmentVerification,
    );
  }
}

class _TestComposerController
    extends ComposerControllerBase<_TestComposerState> {
  _TestComposerController(this._args);

  final _TestArgs _args;
  ComposerSubmissionOutcome outcome = const ComposerSubmissionOutcome.success(
    rawDetail: 'ok',
  );
  Future<ComposerSubmissionOutcome>? outcomeFuture;
  int performSubmitCallCount = 0;

  @override
  ComposerDraftIdentity get draftIdentity => _args.identity;

  @override
  String get uploadFid => _args.fid;

  @override
  Future<_TestComposerState> buildInitialState({
    required ComposerDraftSnapshot? restoredDraft,
    required ComposerPreferences preferences,
  }) async {
    return _TestComposerState.initial(
      message: restoredDraft?.message ?? '',
      useSignature:
          restoredDraft?.useSignature ?? preferences.newDraftUseSignature,
      restoredDraft: restoredDraft != null,
      imageAttachments:
          restoredDraft?.imageAttachments ?? const <ComposerImageAttachment>[],
    );
  }

  @override
  _TestComposerState applyPatch(
    _TestComposerState current,
    ComposerStatePatch patch,
  ) {
    return current.copyFromPatch(patch);
  }

  @override
  Future<ComposerSubmissionOutcome> performSubmit({
    required _TestComposerState state,
    required List<String> uploadedAids,
  }) async {
    performSubmitCallCount += 1;
    final pending = outcomeFuture;
    if (pending != null) {
      return pending;
    }
    return outcome;
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

class _FakeImagePicker implements ComposerImagePicker {
  _FakeImagePicker({this.images = const <ComposerPickedImage>[]});

  final List<ComposerPickedImage> images;

  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async => images;
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
              cachePath: event.uploadedImage!.cachePath,
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

class _ControllableUploadCoordinator implements ComposerImageUploadCoordinator {
  final StreamController<ComposerImageUploadEvent> _events =
      StreamController<ComposerImageUploadEvent>.broadcast();
  String? _localId;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) {
    cancelled = false;
    _localId = attachments.single.localId;
    return _events.stream;
  }

  void emitStarted() {
    _events.add(
      ComposerImageUploadEvent.started(
        localId: _localId!,
        current: 1,
        total: 1,
      ),
    );
  }

  void emitUploaded({required String aid}) {
    _events.add(
      ComposerImageUploadEvent.uploaded(
        localId: _localId!,
        current: 1,
        total: 1,
        uploadedImage: ComposerUploadedImage(
          localId: _localId!,
          aid: aid,
          uploadedAt: DateTime.now(),
        ),
      ),
    );
  }

  void emitCompleted() {
    _events.add(const ComposerImageUploadEvent.completed(total: 1));
  }

  Future<void> close() => _events.close();
}

ProviderContainer _buildContainer({
  ComposerDraftRepository? draftRepository,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
  ComposerPreferencesRepository? composerPreferencesRepository,
  ComposerDraftAttachmentVerificationService? verificationService,
  ComposerUploadCacheStorage? cacheStorage,
}) {
  return ProviderContainer(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        composerPreferencesRepository ?? _MemoryComposerPreferencesRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(
        imagePicker ?? _FakeImagePicker(),
      ),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        imageUploadCoordinator ?? _FakeUploadCoordinator(),
      ),
      if (cacheStorage != null)
        composerUploadCacheStorageProvider.overrideWithValue(cacheStorage),
      if (verificationService != null)
        composerDraftAttachmentVerificationServiceProvider.overrideWithValue(
          verificationService,
        ),
    ],
  );
}

class _RecordingUploadCacheStorage implements ComposerUploadCacheStorage {
  final List<String> deletedPaths = <String>[];

  @override
  Future<bool> deleteCachePathIfOwned(String? cachePath) async {
    final normalized = cachePath?.trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    deletedPaths.add(normalized);
    return true;
  }
}

class _ControllableDraftVerificationService
    implements ComposerDraftAttachmentVerificationService {
  final Completer<ComposerDraftAttachmentVerificationResult> _retry =
      Completer<ComposerDraftAttachmentVerificationResult>();
  var _callCount = 0;
  ComposerDraftSnapshot? _retryDraft;

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) async {
    _callCount += 1;
    if (_callCount == 1) {
      return ComposerDraftAttachmentVerificationResult(
        draft: draft,
        verification: ComposerDraftAttachmentVerification.failed(
          unverifiedAids: const <String>{'12'},
        ),
      );
    }
    _retryDraft = draft;
    return _retry.future;
  }

  void completeRetryWithInvalidAid(String aid) {
    final draft = _retryDraft!;
    _retry.complete(
      ComposerDraftAttachmentVerificationResult(
        draft: ComposerDraftSnapshot(
          identity: draft.identity,
          message: draft.message,
          subject: draft.subject,
          extras: draft.extras,
          useSignature: draft.useSignature,
          updatedAt: draft.updatedAt,
          imageAttachments: [
            for (final attachment in draft.imageAttachments)
              if (attachment.aid?.trim() != aid) attachment,
          ],
        ),
        verification: ComposerDraftAttachmentVerification.verified(
          imagesByAid: const {},
          checkedAids: <String>{aid},
          invalidAidCount: 1,
        ),
      ),
    );
  }
}

ProviderSubscription<AsyncValue<_TestComposerState>> _keepAlive(
  ProviderContainer container,
  _TestArgs args,
) {
  return container.listen<AsyncValue<_TestComposerState>>(
    _testControllerProvider(args),
    (_, _) {},
  );
}

Future<void> _drain({int rounds = 4}) async {
  for (var i = 0; i < rounds; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
